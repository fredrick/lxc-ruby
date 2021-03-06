module LXC
  class Container
    attr_accessor :name
    attr_reader   :state
    attr_reader   :pid

    # Initialize a new LXC::Container instance
    # @param [String] name container name
    # @return [LXC::Container] container instance
    def initialize(name)
      @name = name
    end

    # Get container attributes hash
    # @return [Hash]
    def to_hash
      status
      {'name' => name, 'state' => state, 'pid' => pid}
    end

    # Get current status of container
    # @return [Hash] hash with :state and :pid attributes
    def status
      str    = LXC.run('info', '-n', name)
      @state = str.scan(/^state:\s+([\w]+)$/).flatten.first
      @pid   = str.scan(/^pid:\s+(-?[\d]+)$/).flatten.first
      {:state => @state, :pid => @pid}
    end

    # Check if container exists
    # @return [Boolean]
    def exists?
      LXC.run('ls').split("\n").uniq.include?(name)
    end

    # Check if container is running
    # @return [Boolean]
    def running?
      status[:state] == 'RUNNING'
    end

    # Check if container is frozen
    # @return [Boolean]
    def frozen?
      status[:state] == 'FROZEN'
    end

    # Start container
    # @return [Hash] container status hash
    def start
      LXC.run('start', '-d', '-n', name)
      status
    end

    # Stop container
    # @return [Hash] container status hash
    def stop
      LXC.run('stop', '-n', name)
      status
    end

    # Restart container
    # @return [Hash] container status hash
    def restart
      stop
      start
    end

    # Freeze container
    # @return [Hash] container status hash
    def freeze
      LXC.run('freeze', '-n', name)
      status
    end

    # Unfreeze container
    # @return [Hash] container status hash
    def unfreeze
      LXC.run('unfreeze', '-n', name)
      status
    end

    # Wait for container to change status
    # @param [String] state state name
    def wait(state)
      if !LXC::Shell.valid_state?(state)
        raise ArgumentError, "Invalid container state: #{state}"
      end
      LXC.run('wait', '-n', name, '-s', state)
    end

    # Get container memory usage in bytes
    # @return [Integer]
    def memory_usage
      LXC.run('cgroup', '-n', name, 'memory.usage_in_bytes').strip.to_i
    end

    # Get container memory limit in bytes
    # @return [Integer]
    def memory_limit
      LXC.run('cgroup', '-n', name, 'memory.limit_in_bytes').strip.to_i
    end

    # Get container processes
    # @return [Array] list of all processes
    def processes
      raise ContainerError, "Container is not running" if !running?
      str = LXC.run('ps', '-n', name, '--', '-eo pid,user,%cpu,%mem,args').strip
      lines = str.split("\n") ; lines.delete_at(0)
      lines.map { |l| parse_process_line(l) }
    end

    # Create a new container
    # @param [String] path path to container config file or [Hash] options
    # @return [Boolean]
    def create(path)
      raise ContainerError, "Container already exists." if exists?
      if path.is_a?(Hash)
        args = "-n #{name}"

        if !!path[:config_file]
          unless File.exists?(path[:config_file])
            raise ArgumentError, "File #{path[:config_file]} does not exist."
          end
          args += " -f #{path[:config_file]}"
        end

        if !!path[:template]
          template_path = "/usr/lib/lxc/templates/lxc-#{path[:template]}"
          unless File.exists?(template_path)
            raise ArgumentError, "Template #{path[:template]} does not exist."
          end
          args += " -t #{path[:template]}"
        end

        args += " -B #{path[:backingstore]}" if !!path[:backingstore]
        args += " -- #{path[:template_options].join(' ')}".strip if !!path[:template_options]

        LXC.run('create', args)
        exists?
      else
        raise ArgumentError, "File #{path} does not exist." unless File.exists?(path)
        LXC.run('create', '-n', name, '-f', path)
        exists?
      end
    end

    # Clone to a new container from self
    # @param [String] target name of new container
    # @return [LXC::Container] new container instance
    def clone_to(target)
      raise ContainerError, "Container does not exist." unless exists?
      if self.class.new(target).exists?
        raise ContainerError, "New container already exists."
      end

      LXC.run('clone', '-o', name, '-n', target)
      self.class.new target
    end

    # Create a new container from an existing container
    # @param [String] source name of existing container
    # @return [Boolean]
    def clone_from(source)
      raise ContainerError, "Container already exists." if exists?
      unless self.class.new(source).exists?
        raise ContainerError, "Source container does not exist."
      end

      LXC.run('clone', '-o', source, '-n', name)
      exists?
    end

    # Destroy the container 
    # @param [Boolean] force force destruction
    # @return [Boolean] true if container was destroyed
    #
    # If container is running and `force` parameter is true
    # it will be stopped first. Otherwise it will raise exception.
    #
    def destroy(force=false)
      raise ContainerError, "Container does not exist." unless exists?
      if running?
        if force
          # This will force stop and destroy container automatically
          LXC.run('destroy', '-n', '-f', name)
        else
          raise ContainerError, "Container is running. Stop it first or use force=true"
        end
      else
        LXC.run('destroy', '-n', name)
      end  
      !exists?
    end

    private

    def parse_process_line(line)
      chunks = line.split(' ')
      chunks.delete_at(0)

      pid     = chunks.shift
      user    = chunks.shift
      cpu     = chunks.shift
      mem     = chunks.shift
      command = chunks.shift
      args    = chunks.join(' ')

      {
        'pid'     => pid,
        'user'    => user,
        'cpu'     => cpu,
        'memory'  => mem,
        'command' => command,
        'args'    => args
      }
    end
  end
end