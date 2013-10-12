require 'digest/sha1'

module VagrantPlugins
  module Vocker
    class DockerClient
      def initialize(machine)
        @machine = machine
      end

      def pull_images(*images)
        @machine.communicate.tap do |comm|
          images.each do |image|
            comm.sudo("docker images | grep -q #{image} || docker pull #{image}")
          end
        end
      end

      def start_service
        if !daemon_running? && @machine.guest.capability?(:docker_start_service)
          @machine.guest.capability(:docker_start_service)
        end
      end

      def daemon_running?
        @machine.communicate.test('test -f /var/run/docker.pid')
      end

      def run(containers)
        containers.each do |name, config|
          cids_dir = "/var/lib/vocker/cids"
          config[:cidfile] ||= "#{cids_dir}/#{Digest::SHA1.hexdigest name}"

          @machine.communicate.sudo("mkdir -p #{cids_dir}")
          run_container(config)
        end
      end

      def run_container(config)
        raise "Container's cidfile was not provided!" unless config[:cidfile]

        id = "$(cat #{config[:cidfile]})"

        if container_exist?(id)
          start_container(id)
        else
          create_container(config)
        end
      end

      def container_exist?(id)
        @machine.communicate.test("sudo docker ps -a -q | grep -q #{id}")
      end

      def start_container(id)
        unless container_running?(id)
          @machine.communicate.sudo("docker start #{id}")
        end
      end

      def container_running?(id)
        @machine.communicate.test("sudo docker ps -q | grep #{id}")
      end

      def create_container(config)
        args = "-cidfile=#{config[:cidfile]} -d"
        args << " -dns=#{config[:dns]}" if config[:dns]
        args << " #{config[:additional_run_args]}" if config[:additional_run_args]
        @machine.communicate.sudo %[
          rm -f #{config[:cidfile]}
          docker run #{args} #{config[:image]} #{config[:cmd]}
        ]
      end
    end
  end
end
