FROM ubuntu-debootstrap:14.04

RUN apt-get update && apt-get --yes install nginx curl && apt-get clean

RUN curl -L  https://github.com/coreos/etcd/releases/download/v0.5.0-alpha.4/etcd-v0.5.0-alpha.4-linux-amd64.tar.gz -o etcd-v0.5.0-alpha.4-linux-amd64.tar.gz
RUN tar xzvf etcd-v0.5.0-alpha.4-linux-amd64.tar.gz && rm etcd-v0.5.0-alpha.4-linux-amd64.tar.gz && mv etcd-v0.5.0-alpha.4-linux-amd64/etcdctl /bin/

ADD ./conf/ /etc/nginx/sites-enabled/
ADD ./static/ /usr/share/nginx/www/
ADD ./app/	/


EXPOSE 80

CMD ["/server"]
