# Container build file for the @merseyshipping twitter bot
FROM ruby:2.1
MAINTAINER adrianm@mcqn.com

# Install into /var/local/merseyshipping
RUN mkdir /var/local/merseyshipping
WORKDIR /var/local/merseyshipping

# Install prerequisites
ADD Gemfile .
RUN bundle install

# Copy the scripts over
ADD ship.rb .
ADD MerseyTwitterer.rb .

# And kick things off...
CMD ruby /var/local/merseyshipping/MerseyTwitterer.rb
