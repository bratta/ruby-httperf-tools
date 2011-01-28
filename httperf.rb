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
require 'ostruct'
require 'yaml'
require 'base64'
require 'ruport'

VALID_OPTIONS = ['server', 'rate', 'low_rate', 'high_rate', 'rate_step',
  'wait_time', 'port', 'connections', 'send_buffer', 'recv_buffer', 'uri_list',
  'httperf', 'host', 'username', 'password', 'num_call', 'hog']

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

      results = {}
      report = Table(:column_names => ['rate', 'conn/s', 'req/s',
                     'replies/s avg', 'errors', '5xx status', 'net io (KB/s)'])

      if not @options.low_rate or not @options.high_rate
        @options.low_rate = @options.high_rate = @options.rate
      end

      if @options.low_rate and @options.high_rate
        (@options.low_rate..@options.high_rate).step(@options.rate_step) do |rate|
          results[rate] = run_httperf rate
          report << results[rate].merge({'rate' => rate})

          puts report.to_s
          puts results[rate]['output'] if (results[rate]['errors'].to_i > 0 or
              results[rate]['5xx status'].to_i > 0)
        end
      else
      end
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

  def run_httperf rate=nil
    @options.uri_list.each do |uri|
      authentication = get_authentication_string()
      cmd =  "#{@options.httperf} --client=0/1 --server=#{@options.server} "
      cmd << "--port=#{@options.port} --uri=\"#{uri}\" "
      cmd << "--rate=#{rate or @options.rate} "
      cmd << "--send-buffer=#{@options.send_buffer} "
      cmd << "--recv-buffer=#{@options.recv_buffer} "
      cmd << "--add-header=\"Host:#{@options.host}\\n#{authentication}\" "
      cmd << "--num-conns=#{@options.connections} "
      cmd << "--num-call=#{@options.num_call} "
      cmd << "--hog" if @options.hog

      res = Hash.new("")
      IO.popen("#{cmd} 2>&1") do |pipe|
        puts "\n#{cmd}"
        while((line = pipe.gets))
          res['output'] += line

          case line
          when /^Total: .*replies (\d+)/ then res['replies'] = $1
          when /^Connection rate: (\d+\.\d)/ then res['conn/s'] = $1
          when /^Request rate: (\d+\.\d)/ then res['req/s'] = $1
          when /^Reply time .* response (\d+\.\d)/ then res['reply time'] = $1
          when /^Net I\/O: (\d+\.\d)/ then res['net io (KB/s)'] = $1
          when /^Errors: total (\d+)/ then res['errors'] = $1
          when /^Reply rate .*min (\d+\.\d) avg (\d+\.\d) max (\d+\.\d) stddev (\d+\.\d)/ then
            res['replies/s min'] = $1
            res['replies/s avg'] = $2
            res['replies/s max'] = $3
            res['replies/s stddev'] = $4
          when /^Reply status: 1xx=\d+ 2xx=\d+ 3xx=\d+ 4xx=\d+ 5xx=(\d+)/ then res['5xx status'] = $1
          end
        end
      end
      return res
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

    # If there is a config option set and the file doesnt' exist, then we have a
    # problem
    if (@options.config && !File::exists?(File.expand_path(@options.config)))
      puts "Invalid configuration file path #{@options.config}"
      valid = false
    end

    valid
  end

  # Show the usage statement
  def output_usage
    output_version
  end

  def output_version
    puts "#{File.basename(__FILE__)} version #{VERSION}"
  end

  private

  # Check to see if httperf is available
  def check_for_httperf
    if (!@options.httperf or @options.httperf.empty? or
        !File.exist?(File.expand_path(@options.httperf)))
      puts "Cannot find a valid httperf binary. Check your config and try again"
      exit(1)
    end
  end

  # Set the default options for the script.
  def set_defaults
    @options.config      = nil                    # By default, don't use a config
    @options.server      = 'localhost'            # Run on the local machine
    @options.host        = 'localhost'            # Host: header to use
    @options.rate        = 50                     # httperf rate
    @options.low_rate    = nil                    # starting request rate, for doing multiple httperf runs
    @options.high_rate   = nil                    # max request rate
    @options.rate_step   = 10                     # Among to raise the rate per httperf run
    @options.wait_time   = 120                    # Time to wait between httperf runs
    @options.port        = 80                     # By default, use http
    @options.connections = 200                    # Use 200 connections to the URL
    @options.num_call = 10
    @options.send_buffer = 4096                   # Send buffer
    @options.recv_buffer = 16384                  # Receive buffer
    @options.uri_list    = ['/']                  # By default, only hit the homepage
    @options.httperf     = `which httperf`.chomp  # Path to httperf (required, obviously!)
    @options.username    = nil                    # Basic auth - username
    @options.password    = nil                    # Basic auth - password
    @options.hog         = true                   # Use as many TCP ports as neccessary
  end

  def get_authentication_string
    authentication = ''
    if (@options.username && @options.password)
      encoded = Base64.encode64(
          "#{@options.username}:#{@options.password}").chomp
      authentication = "Authorization: Basic #{encoded}\\n"
    end
    authentication
  end
end

runner = HttperfRunner.new(ARGV, STDIN)
runner.run
