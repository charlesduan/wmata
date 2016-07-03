#!/usr/bin/ruby -w

require './wmata.rb'
require 'readline'
require 'shellwords'

class WmataRunner

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
    @wmata = Wmata.new('838aefdf7f0047649fbea62ddcd0e32a')
    @commands = self.class.commands
  end

  def run
    loop do
      line = Readline.readline('wmata> ', true)
      cmd, *args = line.shellsplit
      next unless cmd

      begin
        dispatch(cmd, *args)
      rescue
        warn("#{$!.message}:\n#{$!.backtrace.join("\n")}")
      end
    end
  end

  def dispatch(command, *args)
    send("cmd_#{command}", *args)
  end

  def method_missing(name, *args)
    if name.to_s =~ /^cmd_/
      STDERR.puts("Command not found: #{name.to_s.sub(/^cmd_/, '')}")
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
  end

  def cmd_quit
    exit
  end

  def cmd_exit
    exit
  end

  def cmd_lines
    l = @wmata.lines
    l.keys.sort.each do |code|
      puts "#{code}: #{l[code]}"
    end
  end

  def cmd_find(search)
    s = @wmata.all_stations
    s.keys.select { |x|
      @wmata.station_name(x) =~ /#{search}/i
    }.sort.each do |name|
      puts "#{name}: #{@wmata.station_name(name)}"
    end
  end

  def cmd_station(code)
    p @wmata.station_info(code)
  end

  def cmd_next(*stations)
    @wmata.next_trains(stations).each do |prediction|
      if prediction.destination
        destination = @wmata.station_name(prediction.destination)
      else
        destination = '(unknown destination)'
      end
      printf("% 3s %2s Trk %1s   %s => %s\n", prediction.min, prediction.line,
             prediction.group,
             @wmata.station_name(prediction.location), destination)
    end
  end

  def cmd_incidents
    @wmata.rail_incidents.each do |incident|
      puts "#{incident.lines.map { |x| @wmata.lines[x] }.join(", ")} " + \
        "Line#{"s" if incident.lines.count > 1}:"
      puts incident.text
      puts ""
    end
  end

  def cmd_bus_name(route)
    puts @wmata.bus_name(route)
  end

  def cmd_bus_info(route, dir)
    puts @wmata.bus_direction(route, dir).join(" to ")
    @wmata.bus_stops(route, dir).each do |id, name|
      puts "  #{id}: #{name}"
    end
  end

  def cmd_bus_routes
    r = @wmata.bus_routes
    r.keys.sort.each do |route|
      puts "#{route} => #{r[route]}"
    end
  end

end

WmataRunner.new.run
