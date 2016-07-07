#!/usr/bin/ruby

require './em-wmata.rb'
require './em-cabi.rb'
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

  def update_periodic
  end

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

  def draw_name(win, name)
    win.setpos(0, 0)
    win.attron(Curses::A_BOLD)
    win.addstr(name[0, win.maxx])
    win.attroff(Curses::A_BOLD)
  end

end

class Incidents

  include Curses
  include WindowManager

  def initialize
    @linewin = Window.new(1, 6, lines - 1, 0)
    @msgwin = Window.new(1, cols - 7, lines - 1, 7)
    @messages = []
  end

  def setup_window
    @msgwin.resize(1, cols - 7)
    @linewin.move(lines - 1, 0)
    @msgwin.move(lines - 1, 7)
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

class BusSet
  include Curses
  include WindowManager

  def initialize(params)
    @params = params
    @params[:location] = [ @params[:location] ].flatten
    @predictions = []
  end

  attr_accessor :params

  def setup_window(height, ypos)
    if @win
      @win.clear
      @win.refresh
      @win.resize(height, cols)
      @win.move(ypos, 0)
      @win.refresh
    else
      @win = Window.new(height, cols, ypos, 0)
    end
    @allocation = allocate_space(
      cols, [ [ 2, 3, 6 ], [ 2 ], [ 3 ], [ 2 ], 10..30 ]
    )
    @win.clear
    draw
  end

  def clear_data
    @predictions = []
  end

  def update_data(predictions)
    @predictions += predictions.select { |x|
      (!@params[:line] || x.line == @params[:line]) &&
        (!@params[:group] || x.group == @params[:group])
    }
    @predictions.sort!
    draw
  end

  def location
    @params[:location]
  end

  def draw
    @win.clear
    @win.setpos(0, 0)
    @win.attron(A_BOLD)
    @win.addstr(@params[:name][0, @win.maxx])
    @win.attroff(A_BOLD)

    @predictions.each_with_index do |prediction, i|
      break if i >= @win.maxy - 1
      @win.setpos(i + 1, 0)
      @win.addstr(format_time(prediction.min.to_s) + "  ")

      @win.addstr(prediction.line.ljust(3) + "  ")

      @win.addstr(prediction.direction[0, @allocation[4]])
    end
    @win.refresh
  end

end

class RailSet
  include Curses
  include WindowManager

  def initialize(params)
    @allocation = allocate_space(
      cols, [ [ 2, 3, 6 ], [ 2 ], [ 2 ], [ 2, 5 ], 10..30 ]
    )
    @params = params
    @predictions = []
  end

  attr_accessor :params

  def location
    return params[:location]
  end

  def setup_window(height, ypos)
    if @win
      @win.clear
      @win.refresh
      @win.resize(height, cols)
      @win.move(ypos, 0)
      @win.refresh
    else
      @win = Window.new(height, cols, ypos, 0)
    end
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
    @win.clear
    draw_name(@win, @params[:name])

    @predictions.each_with_index do |prediction, i|
      break if i >= @win.maxy - 1
      @win.setpos(i + 1, 0)
      @win.addstr(format_time(prediction.min) + "  ")

      @win.attron(color_pair(color_for(prediction.line)))
      @win.addstr(prediction.line)
      @win.attroff(color_pair(color_for(prediction.line)))

      if @allocation[3] == 5
        @win.addstr("  #{(prediction.car || ' ')[0]}  ")
      else
        @win.addstr("  ")
      end

      @win.addstr(prediction.destination_name[0, @allocation[4]])
    end
    @win.refresh
  end

end

class BikeSet
  include Curses
  include WindowManager

  def initialize(params)
    @params = params
    @params[:name] ||= 'Capital Bikeshare'
    @cabi = EM::CapitalBikeshare.new
    @station_ids = params[:station_ids]
    @station_data = Hash[@station_ids.map { |x| [ x, {} ] }]
    @station_ids.each do |station_id|
      @cabi.station_name(station_id) do |name|
        @station_data[station_id][:name] = name
        draw
      end
    end
  end
  def setup_window(height, ypos)
    if @win
      @win.clear
      @win.refresh
      @win.resize(height, cols)
      @win.move(ypos, 0)
    else
      @win = Window.new(height, cols, ypos, 0)
    end
    @allocation = allocate_space(cols, [ [ 5, 9, 17 ], [ 2 ], 10..26 ])
    draw
  end

  def update_data
    @station_ids.each do |station_id|
      @cabi.station_status(station_id) do |status|
        @station_data[station_id][:status] = status
        draw
      end
    end
  end

  def update_periodic
    num_shown = @win.maxy - 1
    if @station_ids.count > num_shown
      @station_ids.rotate!(num_shown)
      draw
    end
  end

  def draw
    return unless @win
    draw_name(@win, @params[:name])
    @station_ids.each_with_index do |station_id, i|
      break if i >= @win.maxy - 1
      data = @station_data[station_id]
      @win.setpos(i + 1, 0)
      if data[:status]
        @win.addstr(data[:status].status_string(@allocation[0]) + "  ")
      else
        @win.addstr(" " * (@allocation[0] + 2))
      end
      @win.addstr((data[:name] || "Station #{station_id}")[0, @allocation[2]])
    end
    @win.refresh
  end
end

class Controller
  include WindowManager

  def initialize(key)
    @wmata = EM::Wmata.new(key)
    @incidents = Incidents.new
    @predictors = []
  end

  def redraw
    allocate_predictors
    @incidents.setup_window
  end

  def update_incidents
    @incidents.update
  end

  def update_incidents_data
    @wmata.rail_incidents do |incidents|
      @incidents.update_data(incidents)
    end
  end

  def update_periodic
    @predictors.each(&:update_periodic)
  end

  def update_predictors(predictors = @predictors)
    rails = []
    predictors.each do |predictor|
      case predictor
      when BikeSet
        predictor.update_data
      when RailSet
        rails.push(predictor)
      when BusSet
        predictor.clear_data
        predictor.location.each do |location|
          @wmata.next_buses(location) do |predictions|
            predictor.update_data(predictions)
          end
        end
      end
    end
    unless rails.empty?
      @wmata.next_trains(rails.map(&:location)) do |predictions|
        rails.each do |railset|
          railset.update_data(predictions)
        end
      end
    end
  end

  def allocate_predictors
    alloc = allocate_space(Curses.lines - 1, [ 2..7 ] * @predictors.count )
    pos = 0
    alloc.zip(@predictors).each do |lines, predictor|
      predictor.setup_window([ lines - 1, 2 ].max, pos)
      pos += lines
    end
  end

  def add_bus_predictor(params)
    if params[:name]
      @predictors << BusSet.new(params)
      allocate_predictors
      update_predictors([ @predictors.last ])
    else
      @wmata.bus_stop_name([ params[:location] ].flatten[0]) do |name|
        params[:name] = name
        add_bus_predictor(params)
      end
    end
  end

  def add_rail_predictor(params)
    if params[:name]
      @predictors << RailSet.new(params)
      allocate_predictors
      update_predictors([ @predictors.last ])
    else
      @wmata.station_name([ params[:location] ].flatten[0]) do |name|
        params[:name] = name
        add_rail_predictor(params)
      end
    end
  end

  def add_bike_predictor(params)
    @predictors << BikeSet.new(params)
    allocate_predictors
    update_predictors([ @predictors.last ])
  end

end

class KeyboardHandler < EventMachine::Connection

  def initialize(controller)
    @controller = controller
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
    @controller.update_incidents_data
  end

  def cmd_r
    @controller.update_predictors
  end

  def cmd_q
    EventMachine.stop_event_loop
  end

  def cmd_d
    @controller.redraw
  end
end


begin
  init_screen
  start_color
  crmode
  curs_set(0)
  WindowManager.better_colors

  (0 .. 255).each do |color|
    init_pair(color, color, COLOR_BLACK)
  end

  EM.run do

    @controller = Controller.new('838aefdf7f0047649fbea62ddcd0e32a')
    @controller.add_rail_predictor(:location => 'A03')
    @controller.add_rail_predictor(:location => 'A04')
    @controller.add_bike_predictor(:station_ids => [ 51, 107, 214, 149, 135 ])
    @controller.add_bus_predictor(:location => %w(1001724 1001744) )

    @controller.update_incidents_data

    EM.open_keyboard(KeyboardHandler, @controller)

    EM.add_periodic_timer(0.1) do
      @controller.update_incidents
    end

    EM.add_periodic_timer(6) do
      @controller.update_periodic
    end

    EM.add_periodic_timer(10) do
      @controller.update_predictors
    end

    EM.add_periodic_timer(60) do
      @controller.update_incidents_data
    end

    Signal.trap("WINCH") do
      EM.schedule do
        close_screen
        refresh
        @controller.redraw
      end
    end
  end

ensure
  close_screen
end

