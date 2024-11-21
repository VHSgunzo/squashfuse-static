# squashfuse-static

Statically linked [squashfuse](https://github.com/vasi/squashfuse) compiled with musl libc

## To get started:
* **Download the latest revision**
```
git clone https://github.com/VHSgunzo/squashfuse-static.git
cd squashfuse-static
```

* **Compile the binaries**
```
# for x86_64
docker run --rm -it -v "$PWD:/root" --platform=linux/amd64 alpine:latest /root/build.sh

# for aarch64 (required qemu-user-static)
docker run --rm -it -v "$PWD:/root" --platform=linux/arm64 alpine:latest /root/build.sh
```

* Or take an already precompiled from the [releases](https://github.com/VHSgunzo/squashfuse-static/releases)
