FINGERPRINT="9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88"
KEYID="0EBFCD88"

# remove old versions of docker
sudo apt-get remove -y docker
sudo apt-get remove -y docker-engine
sudo apt-get remove -y docker.io

# install reequired packages over HTTPS
sudo apt-get install -y apt-transport-https
sudo apt-get install -y ca-certificates
sudo apt-get install -y curl
sudo apt-get install -y software-properties-common

# get Docker's offical GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

# check fingerprint downloaded key
# TODO: write a better test
sudo apt-key fingerprint $KEYID
echo $FINGERPRINT

# add docker repository to the system
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

# update the repo
sudo apt-get update

# install docker-ce
sudo apt-get install -y docker-ce

# If you want Docker to run as a non-root user, you should consider adding
# your user to the docker group like the command underneath but it is against
# good security practices.
# sudo usermode -aG docker $USER
