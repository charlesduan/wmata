#!/usr/bin/ruby

require './em-wmata.rb'
require 'curses'
require 'eventmachine'

include Curses

module WindowManager
  def wordwrap(s, width)
    s.gsub(/(.{1,#{width - 1}})(\s+|\Z)/, "\\1\n").split(/\n/)
  end

  COLOR_MAP = {
    'RD' => COLOR_RED + 8,
    'BL' => COLOR_BLUE + 8,
    'YL' => COLOR_YELLOW + 8,
    'GR' => COLOR_GREEN + 8,
    'OR' => COLOR_MAGENTA + 8,
    'SV' => COLOR_WHITE + 8
  }

  def self.better_colors
    if Curses.colors == 256
      COLOR_MAP['OR'] = 208
      COLOR_MAP['SV'] = 254
    end
  end

  def color_for(line)
    COLOR_MAP[line] || COLOR_WHITE
  end

  def allocate_space(space, allowances)
    max = allowances.map(&:max).inject(:+)
    min = allowances.map(&:min).inject(:+)
    raise "Not enough space" if space < min
    return allowances.map(&:max) if space >= max
    ranges = allowances.map { |l| l.max - l.min }
    extra = (space - min) * 1.0 / ranges.inject(:+)
    allocation = (0 ... allowances.count).map { |i|
      allowances[i].select { |x|
        x <= allowances[i].min + extra * ranges[i]
      }.max
    }
    extra = space - allocation.inject(:+)
    return allocation if extra == 0
    loop do
      new_extra = extra
      p allocation
      allocation = (0 ... allocation.count).map { |i|
        incr = allowances[i].find { |x| x > allocation[i] }
        if incr && incr - allocation[i] <= new_extra
          new_extra -= incr - allocation[i]
          incr
        else
          allocation[i]
        end
      }
      return allocation if new_extra == extra or new_extra == 0
      extra = new_extra
    end
  end

  def update_end
    setpos(lines - 1, cols - 1)
    refresh
  end

end

class Incidents

  include Curses
  include WindowManager

  def initialize(wmata)
    @wmata = wmata
    @linewin = Window.new(1, 6, lines - 1, 0)
    @msgwin = Window.new(1, cols - 7, lines - 1, 7)
    @messages = []
  end

  def setup_window
    @msgwin.resize(1, cols - 7)
    @linewin.setpos(lines - 1, 0)
    @msgwin.setpos(lines - 1, 7)
    @linewin.refresh
    @msgwin.refresh
  end

  def update
    if @current and @pos < @current.length
      @msgwin.setpos(0, 0)
      @msgwin.delch
      @msgwin.setpos(0, @msgwin.maxx - 1)
      @msgwin.addch(@current[@pos])
      @pos += 1
      @msgwin.refresh
    else
      get_next
      update_line
    end
    update_end
  end

  def get_next
    if @messages.empty?
      @current_lines = []
      @current = "*** No alerts ***" + " " * @msgwin.maxx
    else
      m = @messages.shift
      @messages.push(m)
      @current_lines = m.lines
      @current = m.text + " " * @msgwin.maxx
    end
    @pos = 0
  end

  def update_line
    @linewin.clear
    @linewin.setpos(0, 0)
    @current_lines.each do |line|
      @linewin.attron(color_pair(color_for(line)))
      @linewin.addch(line[0])
      @linewin.attroff(color_pair(color_for(line)))
    end
    @linewin.refresh
  end

  def update_data(messages)
    @messages = (@messages & messages) + (messages - @messages)
  end

end

class RailSet
  include Curses
  include WindowManager

  def initialize(wmata, height, ypos, params)
    @wmata = wmata
    @win = Window.new(height, cols, ypos, 0)
    @allocation = allocate_space(
      cols, [ [ 2, 3, 6 ], [ 2 ], [ 2 ], [ 2, 5 ], 10..30 ]
    )
    @params = params
    @predictions = []
  end

  attr_accessor :params

  def format_time(time)
    case @allocation[0]
    when 3 then return time[0, 3].rjust(3)
    when 2
      case time
      when "ARR", "BRD" then return time[0] + time[2]
      when /^\d+$/
        return "**" if time.to_i >= 100
        return "% 2d" % time.to_i
      else
        return "??"
      end
    when 6
      if time =~ /^\d\d?$/ then return "#{time} min".rjust(6)
      else return time.rjust(6)
      end
    end
  end
    

  def setup_window(height, ypos)
    @win.resize(height, cols)
    @win.setpos(ypos, 0)
    @win.refresh
    @allocation = allocate_space(
      cols, [ [ 2, 3, 6 ], [ 2 ], [ 2 ], [ 2, 5 ], 10..30 ]
    )
    @win.clear
    draw
  end

  def update_data(predictions)
    @predictions = predictions.select { |x|
      x.location == @params[:location] &&
        (!@params[:line] || x.line == @params[:line]) &&
        (!@params[:group] || x.group == @params[:group])
    }
    draw
  end

  def draw
    @wmata.station_name(@params[:location]) do |location_name|
      @win.setpos(0, 0)
      @win.addstr(location_name[0, @win.maxx])

      @predictions.each_with_index do |prediction, i|
        break if i >= @win.maxy - 1
        @win.setpos(i + 1, 0)
        @win.addstr(format_time(prediction.min) + "  ")

        @win.attron(color_pair(color_for(prediction.line)))
        @win.addstr(prediction.line)
        @win.attroff(color_pair(color_for(prediction.line)))

        if @allocation[3] == 5
          @win.addstr("  #{prediction.car[0]}  ")
        else
          @win.addstr("  ")
        end

        @win.addstr(prediction.destination_name[0, @allocation[4]])
      end
      @win.refresh
    end
  end

end

class KeyboardHandler < EventMachine::Connection

  def initialize(wmata, windows)
    @wmata = wmata
    @windows = windows
  end

  def receive_data(data)
    send("cmd_#{data.downcase}")
  end

  def method_missing(name, *args)
    unless name.to_s =~ /^cmd_/
      super
    end
  end

  def cmd_i
    @wmata.rail_incidents do |incidents|
      @windows[:incidents].update_data(incidents)
    end
  end

  def cmd_r
    @wmata.next_trains("C01") do |predictions|
      @windows[:predictor1].update_data(predictions)
    end
  end

  def cmd_q
    EventMachine.stop_event_loop
  end
end


begin
  init_screen
  start_color
  crmode
  WindowManager.better_colors

  (0 .. 255).each do |color|
    init_pair(color, color, COLOR_BLACK)
  end

  @wmata = EM::Wmata.new('838aefdf7f0047649fbea62ddcd0e32a')

  @incidents = Incidents.new(@wmata)
  @predictor1 = RailSet.new(@wmata, 6, 0, :location => 'C01')

  @windows = {
    :incidents => @incidents,
    :predictor1 => @predictor1
  }

  EventMachine.run do

    EventMachine.open_keyboard(KeyboardHandler, @wmata, @windows)

    EventMachine.add_periodic_timer(0.1) do
      @incidents.update
    end

    Signal.trap("WINCH") do
      EventMachine.schedule do
        close_screen
        refresh
        @incidents.setup_window
      end
    end
  end

ensure
  close_screen
end

