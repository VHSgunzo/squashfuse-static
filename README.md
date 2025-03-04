# squashfuse-static

Statically linked [squashfuse](https://github.com/vasi/squashfuse) compiled with musl and [mimalloc](https://github.com/microsoft/mimalloc) and glibc

## To get started:
* **Download the latest revision**
```
git clone https://github.com/VHSgunzo/squashfuse-static.git
cd squashfuse-static
```

* **Compile the binaries**
```
# for x86_64 musl
docker run --rm -it -v "$PWD:/root" --platform=linux/amd64 alpine:latest /root/build.sh

# for aarch64 musl (required qemu-user-static)
docker run --rm -it -v "$PWD:/root" --platform=linux/arm64 alpine:latest /root/build.sh

#----------------

# for x86_64 glibc
docker run --rm -it -v "$PWD:/root" --platform=linux/amd64 ubuntu:jammy bash /root/build.sh

# for aarch64 glibc (required qemu-user-static)
docker run --rm -it -v "$PWD:/root" --platform=linux/arm64 ubuntu:jammy bash /root/build.sh
```

* Or take an already precompiled from the [releases](https://github.com/VHSgunzo/squashfuse-static/releases)
