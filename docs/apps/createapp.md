# 新建应用
在微擎面板中，新建应用主要通过填写和配置docker镜像来完成。微擎面板给了两种应用概念，一种是单应用，常规创建使用这种方式，假如你的应用不需要独立的依赖服务，与其他系统共享相关的服务，比如mysql、redis这些是跟其他应用共用的，那么你可以直接创建一个单应用来完成部署。假如你的应用不想跟其他应用共享依赖服务，只想让依赖服务单独为这个应用服务，那么你可以在一个应用中创建多个子应用来实现。

下面我会从这两个方向，做一个示例教程：

## 单应用方案（常规方式）
### 应用1：mysql
#### 配置清单
|应用名|名称|配置项|
|:----|:---|:-----|
|mysql|镜像地址|mysql:8.0|
| |环境变量|MYSQL_ROOT_USERNAME = root<br>MYSQL_ROOT_PASSWORD = 123456|
| |端口|3306|
| |挂载路径|/var/lib/mysql|

#### 创建应用
![image](https://github.com/user-attachments/assets/5c105fc8-284e-4c60-88a1-827472323d58)

#### 创建结果
![image](https://github.com/user-attachments/assets/2bdba593-ae49-4b87-bf78-e8f5e537d25b)

这里的内网域名就是数据库地址。
|应用名|名称|配置项|
|:----|:---|:-----|
|mysql|DB_HOST|mysql-zxvwtfwh.default.svc.cluster.local|

### 应用2：wordpress
这里的DB_HOST、DB_USER、DB_PASSWORD来自已经创建好的mysql应用。DB_NAME是数据库名，可自定义，需要在安装前在mysql命令行界面手动创建出来。

#### 配置清单
|应用名|名称|配置项|
|:----|:---|:-----|
|wordpress|镜像地址|wordpress|
| |环境变量|WORDPRESS_DB_HOST = mysql-zxvwtfwh.default.svc.cluster.local<br>WORDPRESS_DB_USER = root<br>WORDPRESS_DB_PASSWORD = 123456<br>WORDPRESS_DB_NAME = dbname_wordpress|
| |端口|80|
| |挂载路径|/var/www/html|

#### 创建数据库
1. 在应用列表点击进入mysql应用，找到容器列表，然后右侧找到命令行按钮
   ![image](https://github.com/user-attachments/assets/a392b655-e650-40dd-95bd-20f1a306c158)
2. 执行命令，创建数据库
   ```bash
   mysql -uroot -p123456;
   CREATE DATABASE IF NOT EXISTS `dbname_wordpress`;
   ```
   ![image](https://github.com/user-attachments/assets/eb747cdb-9818-41fb-8f79-54a34c506ec3)

#### 创建应用
![image](https://github.com/user-attachments/assets/e7542ee2-dbd4-428c-b1b6-d732f848a628)

#### 添加域名
![image](https://github.com/user-attachments/assets/b8d66db3-70ee-4580-9fd5-2bea061487a6)

#### 访问并安装
![image](https://github.com/user-attachments/assets/61c849ca-75b3-4236-92bb-5eb73a2fe4f0)

## 子应用方案
#### 配置清单
|应用名|名称|配置项|
|:----|:---|:-----|
|mysql|镜像地址|mysql:8.0|
| |环境变量|MYSQL_ROOT_USERNAME = root<br>MYSQL_ROOT_PASSWORD = 123456|
| |端口|3306|
| |挂载路径|/var/lib/mysql|
|wordpress|镜像地址|wordpress|
| |环境变量|WORDPRESS_DB_HOST = mysql-zxvwtfwh.default.svc.cluster.local<br>WORDPRESS_DB_USER = root<br>WORDPRESS_DB_PASSWORD = 123456<br>WORDPRESS_DB_NAME = dbname_wordpress|
| |端口|80|
| |挂载路径|/var/www/html|

#### 创建应用
![image](https://github.com/user-attachments/assets/d9ef1f14-c60e-4cf3-8bb2-052ec6826d0b)

#### 创建结果
![image](https://github.com/user-attachments/assets/a9523eb0-df90-4dfb-8ece-5640f1f319b2)

从应用列表中可以看出来，通过子应用的方式创建出来的应用是一个整体，依赖服务不与其他应用共享使用。而通过单应用独立创建出来的mysql服务，不但可以为单独的wordpress提供服务，也可以为其他需要mysql的应用提供服务，是一个共享使用的概念。
