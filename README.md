# k8s-kafka

### Requirements

```
k8s1.18/1.24 正常运行
```

### kafka-zk version

```
kafka-3.3.2、scala-2.13、zk-3.4.10
```

### Build image

这里用的我的仓库，

deploy1.sh build
deploy1.sh push


### 开启关闭


deploy1.sh start
deploy1.sh stop


### 明码密码登陆机制


#### 服务器配置

1. jaas文件创建：

       
    /opt/kafka/config/kafka_server_jaas.conf
    

2. broker启动的时候设置环境变量KAFKA_OPTS:
    
    
    "-Dlogging.level=INFO -Djava.security.auth.login.config=/opt/kafka/config/kafka_server_jaas.conf"
    
  
3. broker的 变量配置：
    
    
    我这边是没有直接修改server.properties，而是采用override的形式
          --override listeners=SASL_PLAINTEXT://:9092 \
          --override advertised.listeners=SASL_PLAINTEXT://10.0.22.120:9092 \
          --override security.inter.broker.protocol=SASL_PLAINTEXT \
          --override sasl.mechanism.inter.broker.protocol=PLAIN \
          --override sasl.enabled.mechanisms=PLAIN \
          
          
    如果是单例部署的话，需要设置offsets.topic.replication.factor=1
    
    
#### 客户端配置
    
1. jaas文件创建：

    
    /opt/kafka/config/kafka_client_jaas.conf
    

2. consule脚本重载：
    
    
    以下2脚本会重载export KAFKA_OPTS="-Djava.security.auth.login.config=/opt/kafka/config/kafka_client_jaas.conf"
    kafka-console-consumer.sh
    kafka-console-producer.sh


3. consule修改config下consumer.properties和producer.properties：
    
    
    增加
    security.protocol=SASL_PLAINTEXT
    sasl.mechanism=PLAIN
    

### Deployment

zookeeper依赖，先要把zookeeper部署完成，得到域名：

    zk-0.zk-hs.zookeeper.svc.cluster.local
    zk-1.zk-hs.zookeeper.svc.cluster.local
    zk-2.zk-hs.zookeeper.svc.cluster.local


kafka 依赖与PersistentVolume, 需要优先创建3个PersistentVolume：

      volumeClaimTemplates:
        - metadata:
            name: datadir
          spec:
            accessModes: [ "ReadWriteMany" ]
            storageClassName: kafka
            resources:
              requests:
                storage:  300Mi
            
PersistentVolume部署：

    sudo kubectl apply -f PersistentVolume.yaml
    如果3个PV都是部署在一台机器上的，那么path必须为不一样，共用的会出异常


kafka默认启动的用户id为1000， 用户组id为1000, 需要根据实际情况设置：
          
    securityContext:
        runAsUser: 1000
        fsGroup: 1000
        
需要给予PersistentVolume所在目录的访问权限：
    
    sudo chown -R 1000:1000 /opt/kafka_data
    
   
默认启动的topic是不允许删除的，如果想删除需要设置为true

    --override delete.topic.enable=false
    
    
目前默认容忍master节点可以部署：

    toleration:
      - key: "node-role.kubernetes.io/master"
        operator: "Exists"
        effect: "NoSchedule"
        

各种节点过滤选择器nodeSelector||toleration||affinity，如果机器不多，请注释掉，3个节点放在同一个node就好：    
     
    nodeSelector:
        deploy-queue: "yes"
    toleration:
    - key: "deploy-queue"
      operator: "Exists"
      effect: "NoSchedule"
    - key: "deploy-queue"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 3600
    - key: "deploy-queue"
      operator: "Exists"
      effect: "PreferNoSchedule"
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
                - key: "app"
                  operator: In
                  values:
                  - kafka
            topologyKey: "kubernetes.io/hostname"
      podAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
           - weight: 1
             podAffinityTerm:
               labelSelector:
                  matchExpressions:
                    - key: "app"
                      operator: In
                      values:
                      - zk
               topologyKey: "kubernetes.io/hostname"


部署：deploy.sh start


第一个kafka启动完成需要9分钟

查看kafka节点:

    qiteck@server:~/program/docker_service/kafka$ sudo kubectl get pods -n kafka -o wide
    NAME      READY   STATUS    RESTARTS   AGE    IP            NODE     NOMINATED NODE   READINESS GATES
    kafka-0   1/1     Running   0          9m6s   10.244.1.40   server   <none>           <none>
    kafka-1   1/1     Running   0          54s    10.244.1.41   server   <none>           <none>
    kafka-2   1/1     Running   0          31s    10.244.1.42   server   <none>           <none>


列出当前broker的所有配置项：


    root@kafka-0:/opt/kafka/bin# kafka-configs.sh --bootstrap-server localhost:9092 --entity-type brokers --describe --all
    All configs for broker 0 are:
      log.cleaner.min.compaction.lag.ms=0 sensitive=false synonyms={DEFAULT_CONFIG:log.cleaner.min.compaction.lag.ms=0}
      offsets.topic.num.partitions=50 sensitive=false synonyms={STATIC_BROKER_CONFIG:offsets.topic.num.partitions=50, DEFAULT_CONFIG:offsets.topic.num.partitions=50}
      sasl.oauthbearer.jwks.endpoint.refresh.ms=3600000 sensitive=false synonyms={DEFAULT_CONFIG:sasl.oauthbearer.jwks.endpoint.refresh.ms=3600000}
      log.flush.interval.messages=9223372036854775807 sensitive=false synonyms={STATIC_BROKER_CONFIG:log.flush.interval.messages=9223372036854775807, DEFAULT_CONFIG:log.flush.interval.messages=9223372036854775807}
      controller.socket.timeout.ms=30000 sensitive=false synonyms={STATIC_BROKER_CONFIG:controller.socket.timeout.ms=30000, DEFAULT_CONFIG:controller.socket.timeout.ms=30000}
      principal.builder.class=org.apache.kafka.common.security.authenticator.DefaultKafkaPrincipalBuilder sensitive=false synonyms={DEFAULT_CONFIG:principal.builder.class=org.apache.kafka.common.security.authenticator.DefaultKafkaPrincipalBuilder}
      log.flush.interval.ms=null sensitive=false synonyms={}
      。。。。


### Testing


在kafka-0创建topic：
    
    仅在security.inter.broker.protocol=PLAINTEXT情况下可使用，其他情况暂时不知道如何授权
    
    qiteck@server:~/program/docker_service/kafka$ sudo kubectl exec -it kafka-0 -n kafka -- bash
    root@kafka-0:/# /opt/kafka/bin/kafka-topics.sh --create --topic test --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1
    Created topic test.
    root@kafka-0:/#
    
查看topic列表：
    
    仅在security.inter.broker.protocol=PLAINTEXT情况下可使用，其他情况暂时不知道如何授权
    
    root@kafka-0:/# /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
    test
    
在kafka-0进入topic为test的消费者消息中心：

    root@kafka-0:/# /opt/kafka/bin/kafka-console-consumer.sh --topic test --bootstrap-server localhost:9092 --consumer.config /opt/kafka/config/consumer.properties
    aaa
    bbb
    
在kafka-1进入topic为test的生产者消息中心:

    qiteck@server:~$ sudo kubectl exec -it kafka-1 -n kafka -- bash
    root@kafka-1:/# /opt/kafka/bin/kafka-console-producer.sh --topic test --broker-list localhost:9092 --producer.config /opt/kafka/config/producer.properties
    >aaa
    >bbb
    >

消费者中心会随着生产者中心的增加而增加，测试完成



### 集群部署


    1) broker.id不能重复，1-2-3 
    2) 每个kafka进程需要单独部署，advertised.listeners必须不一样，监听端口不能重复。
        如kafka-1.yaml, kafka-2.yaml, kafka-3.yaml
    3) 每个kafka需要单独的service，映射到nodeport不能重复



### 对外提供服务

    对外提供服务的时候需要配置advertised.listeners=PLAINTEXT://10.0.22.120:9092 ，每个kafka节点配置的listeners point必须不一样。
    注意：advertised.listeners的参数必须是客户端访问的bootstrap_servers，严格限制
    只能一个kafka节点配置一个nodeport point的，然后配置对应的advertised.listeners
    所有如果资源有限，还是先部署一个kafka。
    
    如果是域名：PLAINTEXT://kafka-service1:9092，需要配置/etc/hosts
    
    
    
### zookeeper数据共享问题
    
    如果kafka换集群，比如刚开始搭建1个进程，创建一个topic test；然后搭建3个进程的集群，如果继续使用test topic，kafka将会超时，没有任何答应(python脚本体现出来)。
    kafka集群结构修改，必须要清空zookeeper的数据
    
    
### 报错问题



#### kafka部署报错org.apache.kafka.common.KafkaException: Socket server failed to bind to 10.0.22.121:9092?

    同时同一台机器上面的nodeport端口不能重复，如果3个kafka进程部署在同一台机器上面，那么nodeport必须不一样
    
#### kafka部署报错Configured end points 10.0.22.120:9092 in advertised listeners are already registered by broker 0

    每个kafka进程的advertised.listeners必须是不一样的地址，不能重复

#### 客户端连接报错KafkaTimeoutError: Failed to update metadata after 60.0 secs

    目前遇到2种情况会出现这种问题：
    
    1） advertise.listener没有配置，或者advertise.listener配置的值和bootstrap_servers不一致
        如果advertised.listeners=PLAINTEXT://10.0.22.120:9091， 
        那么 producer = KafkaProducer(bootstrap_servers=['10.0.22.120:9091'])
        
    2） kafka集群没有对外提供访问的能力
        配置的advertised.listeners=PLAINTEXT://10.0.22.120:9091，必须是外网能够访问的地址10.0.22.120:9091，
        可以设置nodePort把9091暴露出来，这样外网就能访问了

    3） kafka集群结构发生变化，使用之前结构创建的topic
        刚开始搭建1个进程，创建一个topic test；
        然后重新搭建3个进程的集群，如果继续使用test topic发送接收数据，kafka将会超时，没有任何答应(python脚本体现出来)
        
        
