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
require 'yaml'
require './ship'

# Hash of ships seen last time we checked, indexed on ship id
newShips = Array.new
# Hash of ships we saw the time before last, indexed on ship id
oldShips = Array.new
# Current ship whose details are being populated, whilst parsing the data
currentShip = nil

# Load our configuration
# Setting can either be provided through environment variables (to
# make deployment via Docker easier) or through a YAML file.  If
# provided in a YAML file then the name of the file MUST be provided
# as a command line parameter to the script
settings = {
  "twitter" => {
    "consumer_key" => ENV["TWITTER_CONSUMER_KEY"],
    "consumer_secret" => ENV["TWITTER_CONSUMER_SECRET"],
    "oauth_key" => ENV["TWITTER_OAUTH_KEY"],
    "oauth_secret" => ENV["TWITTER_OAUTH_SECRET"]
  },
  "log_file" => ENV["LOG_FILE"],
  "verbose" => false
}
# Environment variables come through as strings, so let's work round that
if ENV["VERBOSE"].downcase == "true" || ENV["VERBOSE"] == "1"
  settings["verbose"] = true
end

# See if we should override the settings from a config file
unless ARGV.empty?
  puts "Reading config from "+ARGV[0]
  settings = YAML.load_file(ARGV[0])
end

# Bail if we haven't got the right settings
misconfigured = false
settings["twitter"].each do |k,v|
  if v.nil?
    misconfigured = true
    puts "ERROR: Missing Twitter configuration setting #{k}"
  end
end
if misconfigured
  puts
  puts "Can't continue until configured correctly"
  exit
end

# How much information to dump to stdout, 0 for not much, 1 for lots
verbose = settings["verbose"]

# Expects the secret stuff to be in merseyshipping_keys.rb
twitter_client = Twitter::REST::Client.new do |config|
  config.consumer_key = settings["twitter"]["consumer_key"]
  config.consumer_secret = settings["twitter"]["consumer_secret"]
  config.access_token = settings["twitter"]["oauth_key"]
  config.access_token_secret = settings["twitter"]["oauth_secret"]
end

log_file = nil
unless settings["log_file"].nil? || settings["log_file"] == ""
  log_file = File.open(settings["log_file"], "a")
end

while (1)
  # Download HTML for current ship info
  begin
    puts "Getting data at "+Time.now.to_s
    run_time = Time.now
    resp = Net::HTTP.get_response("www.shipais.com", "/currentmap.php?map=mersey")
    lines = resp.body.split(/[\r\n]+/)

    # Parse it looking for ship coordinate info
    lines.each do |line| 
      # See if it's a positional line
      matchinfo = line.match(/#(pc\d+).*left\:(\d+).*top\:(\d+).*/)
      unless matchinfo.nil?
        # It is - extract the coordinates and ship id
        ship = Ship.new(matchinfo[1])
        ship.x = matchinfo[2]
        ship.y = matchinfo[3]
        newShips.push(ship)
        if verbose
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
        if verbose 
          puts "Found #{currentShip.ship_id}.url => #{currentShip.url}"
        end
      end
      # Or maybe the name
      matchinfo = line.match(/Name.*<td>(.*)<\/td>/)
      unless matchinfo.nil?
        currentShip.name = matchinfo[1]
        if verbose 
          puts "#{currentShip.ship_id} is called #{currentShip.name}"
        end
      end
      # Or the details
      matchinfo = line.match(/Details.*<td>(.*)<\/td>/)
      unless matchinfo.nil?
        currentShip.details = matchinfo[1]
        if verbose 
          puts "#{currentShip.ship_id} is a #{currentShip.details}" 
        end
      end
      # Or the destination
      matchinfo = line.match(/Dest.*<td><i>(.*)<\/i><\/td>/)
      unless matchinfo.nil?
        currentShip.destination = matchinfo[1]
        if verbose 
          puts "#{currentShip.ship_id} is headed for #{currentShip.destination}" 
        end
      end
    end
  
    # Now we've got all the ship info, see if any are coming or going
    newShips.each do |ship|
      if verbose 
        puts "#{ship.ship_id}: #{ship.name} => #{ship.x}, #{ship.y} in_river? #{ship.in_river?.to_s}"
      end
      in_river = ship.in_river? ? "in" : "out"
      log_file.puts "#{run_time.to_i}: [#{ship.ship_id}] >>#{ship.name}<< (#{ship.x},#{ship.y}) #{in_river}" unless log_file.nil?
      log_file.flush unless log_file.nil?
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
          short_url = "http://www.shipais.com#{ship.url}"
          # Including a URL leaves us ~115 characters
          available_space = 115 + short_url.length
          heading = (ship.destination == "") ? "" : " bound for #{ship.destination}"
          message = "#{ship.name} #{ship_details}has entered the river#{heading}.  See #{short_url} for current position"
          if message.length > available_space
            # Try something a bit shorter
            message = "#{ship.name} #{ship_details}entered the river#{heading}.  See #{short_url}"
            if message.length > available_space
              # Still too long
              message = "#{ship.name} #{ship_details}entered the river#{heading}."
              if message.length > available_space
                message = "#{ship.name} entered the river#{heading}."
                if message.length > available_space
                  puts "####### That's one hell of a long ship"
                end
              end
            end
          end
              
          puts message
          # Twitter about it
          begin
            twitter_client.update(message)
            log_file.puts message unless log_file.nil?
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
          short_url = "http://www.shipais.com#{ship.url}"
          # Including a URL leaves us ~115 characters
          available_space = 115 + short_url.length
          heading = (ship.destination == "") ? "" : " bound for #{ship.destination}"
          message = "#{ship.name} #{ship_details}has left the river#{heading}.  See #{short_url} for current position"
          if message.length > available_space
            # Try something a bit shorter
            message = "#{ship.name} #{ship_details}has left the river#{heading}.  See #{short_url}"
            if message.length > available_space
              # Still too long
              message = "#{ship.name} #{ship_details}left the river#{heading}."
              if message.length > available_space
                message = "#{ship.name} left the river#{heading}."
                if message.length > available_space
                  puts "####### That's one hell of a long ship"
                end
              end
            end
          end
          puts message
          # Twitter about it
          begin
            twitter_client.update(message)
            log_file.puts message unless log_file.nil?
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

