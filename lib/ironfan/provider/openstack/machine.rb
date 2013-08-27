module Ironfan
  class Provider
    class OpenStack

      class Machine < Ironfan::IaasProvider::Machine
        delegate :availability_zone, :endpoint, :engine,
          :engine_version, :destroy, :image_ref, :flavor, :flavor_ref, :id, :id=, :name, :state, 
          :networks, :os_ext_sts_vm_state, :os_ext_sts_task_state, :os_ext_sts_power_state,
          :created, 
          :to => :adaptee

        def self.shared?()      false;  end
        def self.multiple?()    false;  end
        def self.resource_type()        :machine;   end
        def self.expected_ids(computer) [computer.server.full_name];   end

        def public_hostname
	    name
	end

        def dns_name
	    name
	end
	
	def public_ip_address
	    networks.first.addresses.first
	end

	def vpc_id
	    return nil if networks.empty?
	    networks.first.name
	end
 
	def flavor_name
	    OpenStack.connection.flavors.find { |f| f.id == flavor["id"]}.name
	end

        def created?
          not ['error', 'deleted', 'soft-delete', 'building', 'resized'].include? os_ext_sts_vm_state
        end

        def deleting?
          os_ext_sts_task_state == "deleting"
        end

        def pending?
          os_ext_sts_power_state == 0
        end

        def creating?
          os_ext_sts_vm_state == "building"
        end

        def rebooting?
          state == "REBOOT" || state == "HARD_REBOOT"
        end

        def available?
          os_ext_sts_vm_state == "active" && os_ext_sts_task_state == nil
        end
      
        def running?
          os_ext_sts_vm_state == "active" && os_ext_sts_task_state == nil
        end

        def stopped? 
          state == "SHUTOFF" || os_ext_sts_power_state == 4
        end

        def perform_after_launch_tasks?
          true
        end

        def to_display(style,values={})
          # style == :minimal
          values["State"] =             os_ext_sts_vm_state.to_sym
          values["Task"] =              os_ext_sts_task_state.nil? ? "None" : os_ext_sts_task_state.to_sym
          values["Created On"] =        created.to_date
          return values if style == :minimal

          # style == :default
          values["Flavor"] =            flavor_name
          values["AZ"] =                availability_zone
          return values if style == :default

          # style == :expanded
          values
        end

        def to_s
          "<%-15s %-12s %-25s>" % [
            self.class.handle, id, name]
        end

        #
        # Discovery
        #
        def self.load!(cluster=nil)
          OpenStack.connection.servers.each do |fs|
            machine = new(:adaptee => fs)
            if (not machine.created?)
              next unless Ironfan.chef_config[:include_terminated]
              remember machine, :append_id => "terminated:#{machine.id}"
            elsif recall? machine.name
              machine.bogus <<                 :duplicate_machines
              recall(machine.name).bogus <<    :duplicate_machines
              remember machine, :append_id => "duplicate:#{machine.id}"
            else # never seen it
              remember machine
            end
            Chef::Log.debug("Loaded #{machine}")
          end
        end

        def receive_adaptee(obj)
          obj = OpenStack.connection.servers.new(obj) if obj.is_a?(Hash)
          super
        end

        # Find active machines that haven't matched, but should have,
        #   make sure all bogus machines have a computer to attach to
        #   for display purposes
        def self.validate_resources!(computers)
          recall.each_value do |machine|
            Chef::Log.debug("validate machine: #{machine}")
            next unless machine.users.empty? and machine.name
            if machine.name.match("^#{computers.cluster.name}-")
              machine.bogus << :unexpected_machine
            end
            next unless machine.bogus?
            fake           = Ironfan::Broker::Computer.new
            fake[:machine] = machine
            fake.name      = machine.name
            machine.users << fake
            computers     << fake
          end
        end

        #
        # Manipulation
        #
        def self.create!(computer)
          return if computer.machine? and computer.machine.created?
          Ironfan.step(computer.name,"creating openstack machine...", :green)
          #
          errors = lint(computer)
          if errors.present? then raise ArgumentError, "Failed validation: #{errors.inspect}" ; end
          #
          launch_desc = launch_description(computer)
          launch_desc[:name] = computer.name
          Chef::Log.debug(JSON.pretty_generate(launch_desc))

          Ironfan.safely do
            fog_server = OpenStack.connection.servers.create(launch_desc)
            machine = Machine.new(:adaptee => fog_server)
            computer.machine = machine
            remember machine, :id => machine.name
            Chef::Log.debug(machine)
#            remember machine, :id => computer.name

            Ironfan.step(fog_server.id,"waiting for machine to be ready", :gray)
            Ironfan.tell_you_thrice     :name           => fog_server.id,
                                        :problem        => "server unavailable",
                                        :error_class    => Fog::Errors::Error do
              fog_server.wait_for { ready? }
		sleep 30
            end
          end
          Chef::Log.debug(computer)
        end

        # @returns [Hash{String, Array}] of 'what you did wrong' => [relevant, info]
        def self.lint(computer)
          cloud = computer.server.cloud(:openstack)
          info  = [computer.name, cloud.inspect]
          errors = {}
          errors
        end

        def self.launch_description(computer)
          cloud = computer.server.cloud(:openstack)
          user_data_hsh =               {
            :chef_server =>             Chef::Config[:chef_server_url],
            :node_name =>               computer.name,
            :organization =>            Chef::Config[:organization],
            :cluster_name =>            computer.server.cluster_name,
            :facet_name =>              computer.server.facet_name,
            :facet_index =>             computer.server.index,
          }


          # main machine info
          description = {
            :image_ref => cloud.image_ref,
            :flavor_ref => cloud.flavor_ref,
            :key_name => cloud.key_name.nil? ? computer.server.cluster_name : cloud.key_name;
#            :user_data		=>	JSON.pretty_generate(user_data_hsh),
          }

          description
        end

        def self.destroy!(computer)
          return unless computer.machine?
          forget computer.machine.name
          computer.machine.destroy
          computer.machine.reload            # show the node as shutting down
        end

        def self.save!(computer)
          return unless computer.machine?
        end
      end

    end
  end
end
