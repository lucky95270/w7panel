# 文件管理
由于容器的特性，默认情况下容器内的文件都是临时文件，无法持久存储，所以不能直接在容器中修改文件，否则一旦容器重启文件就会丢失。通过需要通过挂载持久存储来解决容器内文件数据重启丢失的问题。

基于这个前提，我们演化出了一套文件管理功能，我们将容器内的文件分为<b>临时文件</b>和<b>永久文件</b>两个概念，如果被挂载存储的文件或文件夹，在文件管理列表中会标记为永久文件，否则为临时文件。

### 文件状态
灰色为临时文件，绿色为永久文件。
![image](https://github.com/user-attachments/assets/92f7fcc1-4542-4f92-bf23-69c72d9801fc)

### 一键转换为永久文件
主要利用k8s的configmap方案，将临时文件存储到configmap中，并挂载回对应的文件路径。

编辑文件时，勾选永久文件，可将临时文件一键转换为永久文件。
![image](https://github.com/user-attachments/assets/09a137fd-a8e3-4c0d-a864-e672a6ccc5ac)
上传文件和新建文件时，也有类似操作。
![image](https://github.com/user-attachments/assets/d72f9341-3165-4979-a8ed-26a671a69a79)
![image](https://github.com/user-attachments/assets/082b9853-3df6-4f17-aa24-a258ed0e712e)

### 其他管理功能
其他复制、剪切、压缩、设置权限、重命名、上传文件、新建文件、删除文件可自行探索。
