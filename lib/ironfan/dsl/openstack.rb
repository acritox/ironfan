module Ironfan
  class Dsl

    class Compute < Ironfan::Dsl
      def openstack(*attrs,&block)
        cloud(:openstack, *attrs,&block)
      end
    end

    class OpenStack < Cloud
      magic :provider,                  Whatever,       :default => Ironfan::Provider::OpenStack
      magic :image_id,                  String
      magic :image_name,                String
      magic :flavor,                    String,         :default => 'm1.tiny'
      magic :ssh_identity_dir,          String,         :default => ->{ Chef::Config.openstack_key_dir }
      magic :key_name,                  String
      magic :ssh_user,                  String,         :default => 'ubuntu'

      magic :backing,                   String,         :default => ''
      magic :bits,                      Integer,        :default => "64"
      magic :bootstrap_distro,          String,         :default => 'ubuntu12.04-gems'
      magic :chef_client_script,        String
      magic :cluster,                   String
      magic :cpus,                      String,         :default => "1" 
      magic :datastore,                 String
      magic :dns_servers,		Array
      magic :domain,                    String 
      magic :gateway, 			Array
      magic :ip, 	                String
      magic :memory,                    String,         :default => "4" # Gigabytes
      magic :subnet,			String
      magic :template,                  String
      magic :validation_key,            String,         :default => ->{ IO.read(Chef::Config.validation_key) rescue '' }
      magic :virtual_disks,             Array,          :default => []
      magic :network, 			String,		:default => "VM Network"

      def receive_provider(obj)
        if obj.is_a?(String)
          write_attribute :provider, Gorillib::Inflector.constantize(Gorillib::Inflector.camelize(obj.gsub(/\./, '/')))
        else
          super(obj)
        end
      end

      def ssh_identity_file(computer)
        cluster = computer.server.cluster_name
        "%s/%s.pem" %[ssh_identity_dir, cluster]
      end

      def image_info
        {}
      end

      def image_ref
        result = read_attribute(:image_id) || provider.connection.images.find {|img| img.name == read_attribute(:image_name)}.id
      end

      def flavor_ref
        provider.connection.flavors.find {|flavor| flavor.name == read_attribute(:flavor)}.id
      end

      def implied_volumes
        []
      end

      def to_display(style,values={})
        values
      end

    end
  end
end
