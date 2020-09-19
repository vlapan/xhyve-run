# xhyve-run
Just a wrapper around `xhyve`.

Checkout repository
```
git clone https://github.com/vlapan/xhyve-run.git
```

Run FreeBSD installer for VM named `beaver` using disk with fixed size of `8g`:
```
sudo ./run.sh beaver install -s 8g
```

It will check for latest available release, download it and verify it with expected checksum, if everything is ok it will launch the installer.

The process will exit after you have finished FreeBSD installation, you can start it as a deamon with `1` cpu cap and `640m` of available memory:
```
sudo ./run.sh beaver start -c 1 -m 640m
```
It will give you ip address of the VM, but it is also possible to get it with:
```
sudo ./run.sh beaver ip
``` 

To stop the daemon later:
```
sudo ./run.sh beaver stop
```

You can also run it with attached console:
```
sudo ./run.sh beaver run -c 1 -m 640m
```

It is possible to save VM image as a separate file:
```
sudo ./run.sh beaver save --as=freebsd-clean
```

And to restore some file as VM image later:
```
sudo ./run.sh beaver restore --as=freebsd-clean
```