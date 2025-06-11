cd /var/www/buyer-web
yarn install
yarn build
pm2 restart buyer-web
