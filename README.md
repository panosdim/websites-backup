# websites-backup

Take MySQL database and NGINX sites daily backup

## 1. Set Environment Variable

Set the MySQL root password as an environment variable:

```bash
export MYSQL_ROOT_PASSWORD="your_mysql_root_password"
```

To make this permanent, add it to your `~/.bashrc` or `~/.profile`:

```bash
echo 'export MYSQL_ROOT_PASSWORD="your_mysql_root_password"' >> ~/.bashrc
source ~/.bashrc
```

## 2. Update Container Name (if needed)

If your MySQL Docker container has a different name than "mysql", update the `MYSQL_CONTAINER` variable in `backup.sh`:

```bash
MYSQL_CONTAINER="your_container_name"
```

## 3. Verify Docker Container

Make sure your MySQL container is running:

```bash
docker ps | grep mysql
```

## 4. Test the Connection

Test if the backup script can connect to your Docker MySQL:

```bash
docker exec -i your_container_name mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"
```
