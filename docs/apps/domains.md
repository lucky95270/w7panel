# 域名管理
微擎面板的域名管理实际上是一个强大的网关系统，可以使用对应用的路由转发，也可以对路由设置各种策略，下面我以几个常规操作为例，对域名管理功能进行演示，其他策略功能可自行实验：

### 绑定域名
应用安装完成后，可在域名管理中添加域名来对该应用进行域名绑定，然后将绑定的域名解析到服务器ip上即可访问。
![image](https://github.com/user-attachments/assets/8ed2c01c-8646-4540-bbde-fcfd92f10d1d)

### 子目录转发
添加域名时，默认转发目录为`/`，这里是指访问地址`http://域名/`之后会全部匹配。如果你将目录修改为`/123`，那么访问地址`http://域名/123`之后会全部匹配。下面我将列出一个表格详细说明：
![image](https://github.com/user-attachments/assets/1ddd4ea0-bac5-46cb-889b-432bb1cf8dca)
|匹配类型|目录|示例|
|:----|:---|:-----|
|前缀匹配|/|/<br>/123<br>/a/b/c<br>/a/b?c=1|
|前缀匹配|/123|/123<br>/123/a/b/c<br>/123/a/b?c=1|
|精准匹配|/123|/123|
|正则匹配|/([a-z]+)|/a<br>/abc<br>/ccc|

#### 子目录在子应用场景下的应用
子目录转发在多个子应用中发挥着重要的作用，可以使用一个域名，将不同的目录转发至不同的应用。比如创建了多个子应用，主应用为前端，子应用为后端，那么此时就可以将子目录转发至后端应用，对外保持同一个域名。
![image](https://github.com/user-attachments/assets/1642c4bb-d588-47d1-a08c-04f3849b5102)

### 自动SSL证书
自动SSL证书功能将帮助用户获取免费的https证书，并在证书到期前自动续签自动部署，无需人工干预。注意：开启自动SSL证书的域名需要在公网下可正常访问，不然证书签发机构无法验证域名所有权，会导致签发失败。
![image](https://github.com/user-attachments/assets/ac11197c-940a-4c11-9dd2-dd213b16b266)

### 路由策略
除此之外还有重定义header、跨域设置、重试设置、重定向设置、强制https跳转、重写目录、重写域名等设置，可自行探索。
![image](https://github.com/user-attachments/assets/dce9565c-183d-45b6-bf81-3e203dc8ea92)
![image](https://github.com/user-attachments/assets/f397ff4f-91c4-4687-b437-61bbd04dc89f)
