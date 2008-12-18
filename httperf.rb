#!/usr/bin/env ruby
#
# == Synopsis
# This script utilizes httperf to perform a series of 
# calls to a list of websites, using a simple yaml config
# for its options
#
# == Usage
# httperf.rb [options]
# where [options] is one of the following:
#   -v  --version  Show the version of the script
#   -h  --help     Show this screen
#   -c  --config   The yaml config file
#
# == Examples
# Run the tests using a shared config:
#   httperf.rb -c /data/yourapp/shared/config/httperf.yml
#
# Display the help file:
#   httperf.rb --help
#
# Display the version:
#   httperf.rb --version
#
# == Author
# Tim Gourley (mailto:tgourley@engineyard.com)

require 'rubygems'
require 'optparse' 
require 'rdoc/usage'
require 'ostruct'
require 'yaml'
require 'base64'

VALID_OPTIONS = ['server', 'rate', 'port', 'connections', 'send_buffer', 'recv_buffer', 
                 'uri_list', 'httperf', 'host', 'username', 'password']

class OpenStruct
  def add_new(name, value)
    @table[name.to_sym] = value
    new_ostruct_member(name)
  end  
end

class HttperfRunner
  VERSION = '0.1.0'
  attr_accessor :options

  # Set up the Generator class with default options
  def initialize(arguments, stdin)
    @arguments = arguments
    @stdin = stdin
    @options = OpenStruct.new
    set_defaults
  end

  # Our only public method; this parses our command
  # line arguments and runs the test
  def run
    if parsed_options? && arguments_valid?
      # Try loading the config file
      load_yaml_options
      
      # Check to make sure we have a valid httperf
      check_for_httperf
      
      # Run the script
      run_httperf
    else
      output_usage
    end
  end
  
  def load_yaml_options
    if @options.config
      @options.yaml = YAML::load(File.open(File.expand_path(@options.config)))
      VALID_OPTIONS.each do |opt|
        if @options.yaml[opt]
          @options.add_new(opt, @options.yaml[opt])
        end
      end
    end
  end
  
  def run_httperf
    puts @options.to_s
    @options.uri_list.each do |uri|
      authentication = get_authentication_string()
      cmd =  "#{@options.httperf} --client=0/1 --server=#{@options.server} --port=#{@options.port} --uri=#{uri} "
      cmd << "--rate=#{@options.rate} --send-buffer=#{@options.send_buffer} --recv-buffer=#{@options.recv_buffer} "
      cmd << "--add-header=\"Host:#{@options.host}\\n#{authentication}\""
      cmd << "--num-conns=#{@options.connections} --hog | grep \"Request rate\""
      #puts `#{cmd}`
      puts cmd
    end
  end

  protected

  # Parse valid command line options passed to the script.
  # This also sets up the actions to be taken for various
  # options.
  def parsed_options?
    opts = OptionParser.new
    opts.on('-v', '--version')  { output_version; exit 0 }
    opts.on('-h', '--help')     { output_usage }

    opts.on('-c', '--config s', String) { |config| @options.config = config }

    opts.parse!(@arguments) rescue return false
    true
  end

  # Perform some sanity checks on the options before
  # generating the name
  def arguments_valid?
    valid = true

    # If there is a config option set and the file doesnt' exist, then we have a problem
    if (@options.config && !File::exists?(File.expand_path(@options.config)))
      puts "Invalid configuration file path #{@options.config}"
      valid = false
    end

    valid
  end

  # Show the usage statement
  def output_usage
    output_version
    RDoc::usage('usage') # gets usage from comments above
  end

  def output_version
    puts "#{File.basename(__FILE__)} version #{VERSION}"
  end

  private
  
  # Check to see if httperf is available
  def check_for_httperf
    if !@options.httperf || @options.httperf.empty? || !File.exist?(File.expand_path(@options.httperf))
      puts "Cannot find a valid httperf binary. Check your config and try again!"
      exit(1)
    end
  end

  # Set the default options for the script. 
  def set_defaults    
    @options.config      = nil                    # By default, don't use a config
    @options.server      = 'localhost'            # Run on the local machine
    @options.host        = 'localhost'            # Host: header to use
    @options.rate        = 50                     # httperf rate
    @options.port        = 80                     # By default, use http
    @options.connections = 200                    # Use 200 connections to the URL
    @options.send_buffer = 4096                   # Send buffer
    @options.recv_buffer = 16384                  # Receive buffer
    @options.uri_list    = ['/']                  # By default, only hit the homepage
    @options.httperf     = `which httperf`.chomp  # Path to httperf (required, obviously!)
    @options.username    = nil                    # Basic auth - username
    @options.password    = nil                    # Basic auth - password
  end
  
  def get_authentication_string
    authentication = ''
    if (@options.username && @options.password)
      encoded = Base64.encode64("#{@options.username}:#{@options.password}")
      authentication = "Authorization: Basic #{encoded}\\n"
    end
    authentication
  end
end

runner = HttperfRunner.new(ARGV, STDIN)
runner.run
