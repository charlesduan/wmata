#!/usr/bin/ruby

require 'eventmachine'
require 'curses'

begin
  Curses.crmode
  Curses.init_screen
  Curses.refresh

  class KeyboardHandler < EventMachine::Connection
    def receive_data(data)
      puts "Got `#{data.ord}'"
      EventMachine.stop_event_loop if data == 'q'
    end
  end

  EventMachine.run do

    EventMachine.open_keyboard(KeyboardHandler)
    Signal.trap("WINCH") do
      puts "Got window change"
    end

  end

ensure
  Curses.close_screen
end
