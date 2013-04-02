#!/usr/bin/ruby
#
# Ship - Simple class to wrap ShipAIS munging
#
# (c) Copyright 2009-2013 MCQN Ltd.

class Ship
  attr_accessor :ship_id, :x, :y, :url, :name, :details

  def initialize(ship_id)
    # id - the pcXXX id from the HTML
    @ship_id = ship_id
    # x coord
    @x = 0
    # y coord
    @y = 0
    # url - URL to see the location of the ship
    @url = ""
    # name - Name of the ship
    @name = "Ship"+ship_id
    # Details of the ship (usually the type of vessel)
    @details = ""
  end

  # Check if this boat is currently in the river, or in the bay
  def in_river?
    # This first line crosses from Fort Perch to the corner of Seaforth
    # Container Terminal and so marks the "mouth" of the Mersey
    gradient = -1.75
    offset = 399
    #puts "#{@x.to_i} * #{offset} + #{gradient} > #{@y.to_i}"
    if ((@x.to_i * gradient)+offset) < @y.to_i
      true
    else
      # Unfortunately the line across the mouth also crosses most of the
      # container terminal. Check that it isn't just berthed there
      seaforth_gradient = 2.06
      seaforth_offset = -215
      if ((@x.to_i * seaforth_gradient)+seaforth_offset) < @y.to_i
        # It's not in Seaforth Container Terminal
	false
      else
        true
      end
    end
  end

end

