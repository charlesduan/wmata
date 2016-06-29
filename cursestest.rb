#!/usr/bin/ruby

require 'curses'
include Curses

begin
  init_screen
  start_color
  init_pair(1, COLOR_RED + 8, COLOR_BLACK)
  init_pair(2, COLOR_WHITE + 16, COLOR_BLACK)
  crmode
  setpos(3, 3)
  attron(color_pair(0))
  addstr("Hello world!")
  attroff(color_pair(0))
  setpos(5, 3)
  attron(color_pair(1))
  addstr("Dimensions are #{lines}x#{cols}.")
  attroff(color_pair(1))
  setpos(6, 3)
  attron(color_pair(2))
  addstr("Colors: #{colors}")
  attroff(color_pair(2))
  refresh
  sleep(10)
ensure
  close_screen
end
