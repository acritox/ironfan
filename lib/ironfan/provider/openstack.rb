module Ironfan
  class Provider

    class OpenStack < Ironfan::IaasProvider
      self.handle = :openstack

      def self.resources
        [ Machine ]
      end

      #
      # Utility functions
      #
      def self.connection
        @@connection ||= Fog::Compute.new({
         :provider                       => 'OpenStack',
         :openstack_api_key              => Chef::Config[:knife][:openstack_password],
         :openstack_username             => Chef::Config[:knife][:openstack_username],
         :openstack_auth_url             => Chef::Config[:knife][:openstack_auth_url],
         :openstack_tenant               => Chef::Config[:knife][:openstack_tenant]
        })
      end

      def self.applicable(computer)
        computer.server and computer.server.clouds.include?(:openstack)
      end

    end
  end
end
