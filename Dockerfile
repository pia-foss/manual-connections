# Use Ubuntu 20.04 as the base image
FROM ubuntu:20.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Update and install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    wireguard-tools \
    openvpn \
    git \
    sudo

RUN rm -rf /var/lib/apt/lists/*

# Set up a non-root user
RUN useradd -m -s /bin/bash pia
RUN echo "pia ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory
WORKDIR /home/pia

# Clone the repository
# RUN git clone https://github.com/pia-foss/manual-connections.git
COPY . ./manual-connections

# Set ownership of the cloned repository to the pia user
RUN chown -R pia:pia /home/pia/manual-connections

# # Create a TUN device
RUN mkdir -p /dev/net && \
    mknod /dev/net/tun c 10 200 && \
    chmod 0666 /dev/net/tun

# Switch to the pia user
USER pia

# Set the working directory to the cloned repository
WORKDIR /home/pia/manual-connections

# Make the run_setup.sh script executable
RUN chmod +x run_setup.sh
RUN chmod +x /home/pia/manual-connections/docker-scripts/startup.sh

# Set the startup script as the entry point
CMD ["/home/pia/manual-connections/docker-scripts/startup.sh"]