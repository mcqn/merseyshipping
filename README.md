merseyshipping
==============

Simple ruby script to watch ShipAIS.com and tweet whenever boats leave or enter the river Mersey

Comes with a simple etc/init.d script to allow it to be integrated into monit for montioring, but for simple usage...

 1. cp merseyshipping_keys.example.rb merseyshipping_keys.rb
 1. Edit merseyshipping_keys.rb to contain your Twitter OAuth and Bit.ly API keys
 1. ./MerseyTwitterer.rb

For more background, see https://twitter.com/merseyshipping or http://www.mcqn.com/weblog/connecting_river_mersey_twitter
