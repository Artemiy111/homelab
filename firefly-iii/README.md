# FireFly III

[https://firefly-iii.github.io/kubernetes/]

Как всё удалить если зависло?

```sh
helm repo add firefly-iii https://firefly-iii.github.io/kubernetes/
helm repo update

helm install firefly-iii firefly-iii/firefly-iii-stack -n firefly-iii -f ./values.yaml
```