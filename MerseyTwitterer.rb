#!/usr/bin/ruby
#
# MerseyTwitterer - a script to scrape the ship details from ShipAIS and tweet
# whenever a ship enters or leaves the Mersey
#
# (c) Copyright 2009-2013 MCQN Ltd.

require 'rubygems'
require 'time'
require 'net/http'
require 'twitter'
require 'merseyshipping_keys'
require 'amc_bitly'
require 'ship'

# Rather insecure way to get round the "can't post to Twitter" problem
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

# Store our PID so that init/monit can find us
`echo "#{Process.pid}" > /var/run/rails/MerseyTwitterer.pid`

# Hash of ships seen last time we checked, indexed on ship id
newShips = Array.new
# Hash of ships we saw the time before last, indexed on ship id
oldShips = Array.new
# Current ship whose details are being populated, whilst parsing the data
currentShip = nil
# How much information to dump to stdout, 0 for not much, 1 for lots
verbose = 0

# Expects the secret stuff to be in merseyshipping_keys.rb
twitter_client = Twitter::REST::Client.new do |config|
  config.consumer_key = TWITTER_CONSUMER_KEY
  config.consumer_secret = TWITTER_CONSUMER_SECRET
  config.access_token = TWITTER_OAUTH_KEY
  config.access_token_secret = TWITTER_OAUTH_SECRET
end

while (1)
  # Download HTML for current ship info
  #lines = IO.readlines("ship.html")
  begin
    puts "Getting data at "+Time.now.to_s
    resp = Net::HTTP.get_response("www.shipais.com", "/currentmap.php?map=mersey")
    #lines = resp.body.split('\n')

    # Parse it looking for ship coordinate info
    #lines.each do |line| 
    resp.body.each do |line|

      # See if it's a positional line
      matchinfo = line.match(/#(pc\d+).*left\:(\d+).*top\:(\d+).*/)
      unless matchinfo.nil?
        # It is - extract the coordinates and ship id
        ship = Ship.new(matchinfo[1])
        ship.x = matchinfo[2]
        ship.y = matchinfo[3]
        newShips.push(ship)
        if verbose == 1 
          puts "Newship "+ship.ship_id
        end
      end
      # Or the start of the ship info table
      matchinfo = line.match(/id="(pc\d+)".*href="(.*)">/)
      unless matchinfo.nil?
        # We've found the start of the ship info
        # Find the ship in the newShips array
        newShips.each do |ship|
          # At this point we don't have a name for the ship, but the "ship_id"s
          # will match as this is within the same download.
          # "ship_id"s don't match from one page load to the next
          if ship.ship_id == matchinfo[1]
            currentShip = ship
	  end
        end
        currentShip.url = matchinfo[2]
        if verbose == 1 
          puts "Found #{currentShip.ship_id}.url => #{currentShip.url}"
        end
      end
      # Or maybe the name
      matchinfo = line.match(/Name.*<td>(.*)<\/td>/)
      unless matchinfo.nil?
        currentShip.name = matchinfo[1]
        if verbose == 1 
          puts "#{currentShip.ship_id} is called #{currentShip.name}"
        end
      end
      # Or the details
      matchinfo = line.match(/Details.*<td>(.*)<\/td>/)
      unless matchinfo.nil?
        currentShip.details = matchinfo[1]
        if verbose == 1 
          puts "#{currentShip.ship_id} is a #{currentShip.details}" 
        end
      end
    end
  
    # Now we've got all the ship info, see if any are coming or going
    newShips.each do |ship|
      if verbose == 1 
        puts "#{ship.ship_id}: #{ship.name} => #{ship.x}, #{ship.y} in_river? #{ship.in_river?.to_s}"
      end
      # Find the ship in the oldShips array, if present
      old_ship = nil
      oldShips.each do |os|
        if os.name == ship.name
          old_ship = os
        end
      end
  
      if old_ship
        # We've seen this ship before, so see if it's...
        if ship.in_river? && !old_ship.in_river?
          # ...coming...
          puts "Ship: #{ship.name} => #{ship.x},#{ship.y}"
          puts "OldShip: #{old_ship.name} => #{old_ship.x},#{old_ship.y}"
          if ship.details.empty?
            ship_details = ""
          else
            ship_details = "(#{ship.details}) "
          end
          short_url = BitLy.shorten("http://www.shipais.com#{ship.url}")
          message = "#{ship.name} #{ship_details}has entered the river.  See #{short_url} for current position"
          if message.length > 140
            # Try something a bit shorter
            message = "#{ship.name} #{ship_details}entered the river.  See #{short_url}"
            if message.length > 140
              # Still too long
              message = "#{ship.name} #{ship_details}entered the river."
              if message.length > 140
                puts "####### That's one hell of a long ship"
              end
            end
          end
              
          puts message
          # Twitter about it
          begin
            twitter_client.update(message)
          #rescue Twitter::RESTError => re
          #  puts Time.now.to_s+" RESTError when tweeting."
	  #  puts re.code, re.message, re.uri
          #  sleep 240
          rescue Timeout::Error
            puts Time.now.to_s+" Timeout::Error when tweeting."
            sleep 240
          rescue
            # Not much we can do if something goes wrong, just wait for a bit
            # and then carry on
            puts Time.now.to_s+" Something went wrong when tweeting.  Error was:"
            puts $!
            # Poll slightly less often if there are problems, just to be polite
            sleep 240
          end
        end
        if !ship.in_river? && old_ship.in_river?
          # ...or going
          puts "Ship: #{ship.name} => #{ship.x},#{ship.y}"
          puts "OldShip: #{old_ship.name} => #{old_ship.x},#{old_ship.y}"
          if ship.details.empty?
            ship_details = ""
          else
            ship_details = "(#{ship.details}) "
          end
          short_url = BitLy.shorten("http://www.shipais.com#{ship.url}")
          message = "#{ship.name} #{ship_details}has left the river.  See #{short_url} for current position"
          if message.length > 140
            # Try something a bit shorter
            message = "#{ship.name} #{ship_details}has left the river.  See #{short_url}"
            if message.length > 140
              # Still too long
              message = "#{ship.name} #{ship_details}left the river."
              if message.length > 140
                puts "####### That's one hell of a long ship"
              end
            end
          end
          puts message
          # Twitter about it
          begin
            twitter_client.update(message)
          #rescue Twitter::RESTError => re
          #  puts Time.now.to_s+" RESTError when tweeting."
          #  sleep 240
          rescue Timeout::Error
            puts Time.now.to_s+" Timeout::Error when tweeting."
            sleep 240
          rescue
            # Not much we can do if something goes wrong, just wait for a bit
            # and then carry on
            puts Time.now.to_s+" Something went wrong when tweeting.  Error was:"
            puts $!
            # Poll slightly less often if there are problems, just to be polite
            sleep 240
          end
        end
      end
    end

    # See if there are any ships which have disappeared
    newShipNames = newShips.collect {|s| s.name }
    oldShips.each do |ship|
      unless newShipNames.include?(ship.name)
        puts "#{ship.ship_id} #{ship.name} has disappeared"
      end
    end

    # All these new ships will be old ones in a moment when we've new results
    oldShips = newShips

  rescue Timeout::Error
    puts Time.now.to_s+" Timeout::Error when retrieving ship info."
    sleep 240
  rescue
    # Not much we can do if something goes wrong, just wait for a bit and then
    # carry on
    puts Time.now.to_s+" Something went wrong.  Error was:"
    puts $!
    # Poll slightly less often if there are problems, just to be polite
    sleep 240
  end

  # And we need to clear out newShips
  newShips = Array.new

  # And wait for a bit before getting the next load of data
  sleep 120
end

