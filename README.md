# How to install:

vpskit require Github **username** and **personal access token** to work. View [how to get GH access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token)
`curl -s -o /tmp/install.sh https://raw.githubusercontent.com/Theplus1/vpskit/refs/heads/main/install.sh && bash /tmp/install.sh`

## Setup new VPS for hosting sellpage

Execute command: `vpskit sellpage-hosting`

## Setup new VPS for hosting kyc website

Execute command: `vpskit kyc-hosting`

## Available commands


| Commands              | Description                          |
| ----------------------- | -------------------------------------- |
| `kyc-hosting`         | Initialize hosting for a KYC website |
| `sellpage-hosting`    | Initialize hosting for a Sellpage    |
| `scale-redis`         | Scale a Redis cluster                |
| `scale-redis-revert`  | Revert a Redis cluster scaling       |
| `gh-webhook`          | Setup GitHub webhook for deployment  |
| `add-domain`          | Add a new sellpage domain            |
| `add-domain {domain}` | Quick add a new sellpage domain      |
