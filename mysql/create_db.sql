create user 'cloudreve'@'%' identified by 'cloudreve@MySQL2023';
create database cloudreve;
grant all privileges on cloudreve.* to 'cloudreve'@'%';

create user 'alist'@'%' identified by 'alist@MySQL2023';
create database alist;
grant all privileges on alist.* to 'alist'@'%';

flush privileges;