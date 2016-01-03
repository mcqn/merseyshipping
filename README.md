merseyshipping
==============

Simple ruby script to watch ShipAIS.com and tweet whenever boats leave or enter the river Mersey

Comes with a simple etc/init.d script to allow it to be integrated into monit for montioring, but for simple usage...

 1. cp config.example.yaml config.yaml
 1. Edit config.yaml to contain your Twitter OAuth API keys
 1. ./MerseyTwitterer.rb config.yaml

For more background, see https://twitter.com/merseyshipping or http://www.mcqn.com/weblog/connecting_river_mersey_twitter

## Deploying with Docker

For more advanced use you might want to deploy it as a Docker container.

N.B. You might need to run the docker commands with sudo, depending on your setup

 1. Build the image
    docker build -t mcqnltd/merseyshipping .
 1. Configure your settings.  In the Docker version it uses environment variables rather than the config.yaml file
    cp config.example.env config.env
 1. Edit config.env to contain your Twitter OAuth API keys
 1. Run the image
    docker run --env-file=config.env --name merseyshipping --rm -t -i mcqnltd/merseyshipping
