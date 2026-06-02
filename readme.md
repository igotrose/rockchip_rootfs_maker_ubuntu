## 简介

A set of shell scripts that will build GNU/Linux distribution rootfs image
for rockchip platform.

## 安装依赖

推荐使用Ubuntu20.04及以上版本主机构建根文件系统

```
sudo apt-get install binfmt-support qemu-user-static
sudo dpkg -i ubuntu-build-service/packages/*
sudo apt-get install -f
```

## 构建 Ubuntu20.04镜像（仅支持64bit）

- lite：控制台版，无桌面
- xfce：桌面版，使用xfce桌面套件
- xfce-full：桌面版，使用xfce桌面套件+更多推荐软件包
- gnome：桌面版，使用gnome桌面套件
- gnome-full：桌面版，使用gnome桌面套件+更多推荐软件包

#### step1.构建基础 Ubuntu 系统。
如果没有修改 `mk-base-ubuntu.sh` 脚本中的内容，则不需要重复构建base镜像部分。如果修改了则需要重新构建基础根文件系统
```
# 运行以下脚本，根据提示选择要构建的版本
./mk-base-ubuntu.sh
```
#### step2.添加 rk overlay 层,并打包ubuntu-rootfs镜像
如果修改了`mk-ubuntu-rootfs.sh、overlay、overlay-debug、overlay-firmware、packages`的内容，则需要执行以下命令
```
# 运行以下脚本，根据提示选择要构建处理器版本和ubuntu的版本
./mk-ubuntu-rootfs.sh
```
