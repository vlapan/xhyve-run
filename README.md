sudo ./run.sh beaver install -s 8g

sudo ./run.sh beaver run -c 1 -m 640m

sudo ./run.sh beaver start -c 1 -m 640m
sudo ./run.sh beaver stop

sudo ./run.sh beaver ip

sudo ./run.sh beaver save --as=freebsd-clean
sudo ./run.sh beaver restore --as=freebsd-clean
