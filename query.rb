#!/usr/bin/ruby -w

require 'readline'
require 'shellwords'
require 'eventmachine'
require './em-wmata.rb'
require './em-cabi.rb'
require './em-cache.rb'

class WmataRunner < EM::Connection

  include EM::Protocols::LineText2

  if RUBY_VERSION =~ /^1\./
    def self.commands
      instance_methods(false).grep(/^cmd_/).map { |x| x.sub(/^cmd_/, '') }
    end
  else
    def self.commands
      instance_methods(false).map(&:to_s).grep(/^cmd_/).map { |x|
        x.sub(/^cmd_/, '')
      }
    end
  end
  attr_accessor :commands

  def initialize
    @wmata = EM::Wmata.new('838aefdf7f0047649fbea62ddcd0e32a') do |err|
      puts err
    end
    @cabi = EM::CapitalBikeshare.new do |err| puts err end
    @cache = EmCache.new do |err| puts err end
    @commands = self.class.commands
    prompt
  end

  def prompt
    print "wmata> "
  end

  def receive_line(line)
    cmd, *args = line.shellsplit
    if cmd
      begin
        dispatch(cmd, *args)
      rescue
        warn("#{$!.message}:\n#{$!.backtrace.join("\n")}")
        prompt
      end
    else
      prompt
    end
  end

  def dispatch(command, *args)
    send("cmd_#{command}", *args)
  end

  def method_missing(name, *args)
    if name.to_s =~ /^cmd_/
      STDERR.puts("Command not found: #{name.to_s.sub(/^cmd_/, '')}")
      prompt
    else
      super
    end
  end
  def warn(msg)
    STDERR.puts(msg)
  end

  def cmd_help
    puts "Available commands:"
    puts commands.sort.map { |x| "  #{x}" }.join("\n")
    prompt
  end

  def cmd_quit
    EM.stop
  end

  def cmd_exit
    EM.stop
  end

  def cmd_lines
    @wmata.lines do |l|
      l.keys.sort.each do |code|
        puts "#{code}: #{l[code]}"
      end
      prompt
    end
  end

  def cmd_find(search)
    @wmata.all_stations do |s|
      s.keys.select { |x|
        s[x]['Name'] =~ /#{search}/i
      }.sort.each do |name|
        puts "#{name}: #{s[name]['Name']}"
      end
      prompt
    end
  end

  def cmd_station(code)
    @wmata.station_info(code) do |info|
      p info
      prompt
    end
  end

  def cmd_next(*stations)
    @wmata.next_trains(stations) do |predictions|
      predictions.each do |prediction|
        if prediction.destination
          destination = @wmata.station_name(prediction.destination)
        else
          destination = '(unknown destination)'
        end
        printf("% 3s %2s Trk %1s   %s => %s\n", prediction.min, prediction.line,
               prediction.group,
               @wmata.station_name(prediction.location), destination)
      end
      prompt
    end
  end

  def cmd_incidents
    @wmata.rail_incidents do |incidents|
      incidents.each do |incident|
        puts "#{incident.lines.map { |x| @wmata.lines[x] }.join(", ")} " + \
          "Line#{"s" if incident.lines.count > 1}:"
        puts incident.text
        puts ""
      end
      prompt
    end
  end

  def cmd_bus_stop_name(station)
    @wmata.bus_stop_name(station) do |name|
      puts name
      prompt
    end
  end

  def cmd_bus_info(route, dir)
    @wmata.bus_direction(route, dir) do |dirdata|
      @wmata.bus_stops(route, dir) do |stopdata|
        puts dirdata.join(" to ")
        stopdata.each do |id, name|
          puts "  #{id}: #{name}"
        end
        prompt
      end
    end
  end

  def cmd_bus_routes
    @wmata.bus_routes do |r|
      r.keys.sort.each do |route|
        puts "#{route} => #{r[route]}"
      end
      prompt
    end
  end

  def cmd_cabi_station(station_id)
    @cabi.station_name(station_id) do |name|
      puts "Bikeshare station #{station_id} => #{name}"
      prompt
    end
  end

  def cmd_dns(name)
    @cache.resolve_dns(name) do |r|
      p r
      prompt
    end
  end

end

EM.run do
  EM.open_keyboard(WmataRunner)
end
