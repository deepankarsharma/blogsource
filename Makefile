# Makefile for Hugo project

# Default target
all: build

# Build the site
build:
	hugo --environment production --minify

# Serve the site locally
serve:
	hugo server

# Clean the public directory
clean:
	rm -rf public

# Phony targets
.PHONY: all build serve clean

