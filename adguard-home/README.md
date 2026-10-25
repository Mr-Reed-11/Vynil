# AdGuard Home (bloqueio de anúncios na rede de casa)

Bloqueador de anúncios por DNS: propagandas (Google, YouTube, Facebook,
etc.) são barradas para **todos os aparelhos** que usarem o servidor como
DNS — roteador, TVs e celulares, sem instalar nada neles.

## Instalar (uma vez, no servidor)

```bash
cd ~/Vynil && git pull
docker compose -f adguard-home/docker-compose.yml up -d
```

Abrir `http://<ip-do-servidor>:8093` e seguir o wizard:

- Porta de escuta do DNS: **53** (padrão)
- Porta da interface web: **0.0.0.0:3000** → dashboard fica em `:8093`
  (se o wizard deixar em `:80`, o dashboard é `:8094`)
- Usuário/senha do painel: escolha — é só do painel, não afeta o Vynil

## Ativar na rede de casa

No painel de admin do **roteador**:

1. Ache a configuração de **DHCP / Servidor DNS**
2. Coloque como DNS primário o **IP LAN do servidor** (ex.: `192.168.0.10`
   — não é o `100.x` do Tailscale)
3. Salve; os aparelhos pegam o novo DNS ao reconectar no WiFi

Para testar na hora (DHCP antigo demora a expirar), defina o DNS
manualmente no celular: WiFi → configurações avançadas → DNS = IP LAN do
servidor.

## Testar

- Dashboard, aba "Estatísticas": os "Filtrados" sobem desde a hora em que
  o roteador passou a usar o DNS do servidor.
- De um aparelho da rede:
  `nslookup doubleclick.net <ip-lan-do-servidor>` → deve responder `0.0.0.0`.

## Interferência com o Vynil: nenhuma

- Portas 53 e 8093/8094 não colidem com as do backend (3000 etc.).
- Os dados do bloqueio ficam em `adguard-home/work|conf` no servidor.
- Cada um é um compose/arquivos próprios — um não alcança o outro.

## Manutenção

```bash
# Atualizar
cd ~/Vynil/adguard-home && docker compose pull && docker compose up -d

# Diagnóstico
docker logs adguard-home
```

Se a rede da casa ficar sem internet por causa do bloqueador, no roteador
retorne o DNS ao automático — volta em minutos.
