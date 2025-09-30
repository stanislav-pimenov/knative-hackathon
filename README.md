# knative-hackathon

Установка окружения

1. Установлен Docker Desktop версии > 4.35.  
2. Влючена feature Kubernetes (k8s vesion > 1.30). Если k8s использовался ранее, необходимо прожать `Reset kubernetes cluster`
   
![](img.png)  

3. Для платформ linux и macos выполнить установочный скрипт install_knative_1_17_kourier.sh [install_knative_1_17_kourier.sh](install_knative_1_17.sh)    
```shell
./install_knative_1_17_kourier.sh
``` 
4. Скрипт разверет следующее:
- установит cmd tool kubectl
- установит knative и kourier в качестве ingress
- запустит тестовый сервис echo
- протестирует, что все вышеперечисленное поднялось и взлетело

```shell
curl -H "Host: echo.default.knative.demo.com" 'http://localhost:80/api/v1/metrics?param=value'
{"host":{"hostname":"echo.default.knative.demo.com","ip":"::ffff:127.0.0.1","ips":[]},"http":{"method":"GET","baseUrl":"","originalUrl":"/api/v1/metrics?param=value","protocol":"http"},"request":{"params":{"0":"/api/v1/metrics"},"query":{"param":"value"},"cookies":{},"body":{},"headers":{"host":"echo.default.knative.demo.com","user-agent":"curl/8.7.1","accept":"*/*","forwarded":"for=10.1.0.158;proto=http","k-proxy-request":"activator","x-forwarded-for":"10.1.0.158, 10.1.0.155","x-forwarded-proto":"http","x-request-id":"14dc2cd1-3e69-4116-bd26-ffc1e74573be"}},"environment":{"PATH":"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin","HOSTNAME":"echo-00005-deployment-98847545f-9csbk","EXAMPLE_ENV":"value","PORT":"80","K_REVISION":"echo-00005","K_CONFIGURATION":"echo","K_SERVICE":"echo","KUBERNETES_PORT_443_TCP_ADDR":"10.96.0.1","KUBERNETES_SERVICE_HOST":"10.96.0.1","KUBERNETES_SERVICE_PORT":"443","KUBERNETES_SERVICE_PORT_HTTPS":"443","KUBERNETES_PORT":"tcp://10.96.0.1:443","KUBERNETES_PORT_443_TCP":"tcp://10.96.0.1:443","KUBERNETES_PORT_443_TCP_PROTO":"tcp","KUBERNETES_PORT_443_TCP_PORT":"443","NODE_VERSION":"20.11.0","YARN_VERSION":"1.22.19","HOME":"/root"}}
```   
4. Свои наработки можно запускать аналогично echo сервису из шага 5, меняя image и env переменные если нужно

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: echo
  namespace: default
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"
        autoscaling.knative.dev/maxScale: "5"
        autoscaling.knative.dev/target: "50"
        autoscaling.knative.dev/class: "kpa.autoscaling.knative.dev"
        autoscaling.knative.dev/metric: "rps"
        networking.knative.dev/ingress.class: "kourier.ingress.networking.knative.dev"
    spec:
      containers:
        - image: ealen/echo-server:latest
          ports:
            - containerPort: 80
          env:
            - name: EXAMPLE_ENV
              value: "value"
```

Кратное описание используемых аннотаций knative, определяющий логику масштабирования в зависимости от нагрузки

| Аннотация                                                   | Значение по умолчанию         | Описание                                                                                 |
|-------------------------------------------------------------|-------------------------------|-----------------------------------------------------------------------------------------|
| `autoscaling.knative.dev/minScale`                          | `0`                           | Минимальное количество подов, которые должны быть запущены для ревизии.                 |
| `autoscaling.knative.dev/maxScale`                          | Без ограничения (`∞`)         | Максимальное количество подов, которые могут быть запущены для ревизии.                 |
| `autoscaling.knative.dev/target `                           | `100`                         | Целевое количество запросов на контейнер для автоскейлинга.                             |
| `autoscaling.knative.dev/class`                             | `kpa.autoscaling.knative.dev` | Класс автоскейлинга: `kpa.autoscaling.knative.dev` (по умолчанию) или `hpa`.            |
| `autoscaling.knative.dev/metric`                            | `concurrency`                 | Тип метрики для автоскейлинга: `concurrency` или `rps` (запросы в секунду).             |
