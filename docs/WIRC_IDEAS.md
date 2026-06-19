# Wirc — Ideias Aprovadas (2026-06-18)

## Providers

### Implementados
1. **IRC** — mensagens, presença, canais
2. **RSS** — posts/artigos, feeds cronológicos
3. **Mastodon** — social (ActivityPub): posts, replies, boosts, follows

### Próximos (aprovados)

| Provider | WOM types | Motivo |
|----------|-----------|--------|
| **Nostr** | wom:Post, wom:Signal, wom:Reaction | Protocolo assinado, relay-based. Kind 1→Post, Kind 7→Reaction, Kind 3→Follow. |
| **Bluesky (AT Protocol)** | wom:Post, wom:Follow, wom:Collection | Cresce rápido, API pública, records JSON tipados → WOM quase mecânico. |
| **Hacker News** | wom:Post, wom:Comment, wom:Signal | API Firebase (read-only, sem auth, sem rate limit). Alta qualidade. ~80 linhas. |
| **YouTube (via RSS)** | wom:Post (video), wom:Collection (playlist) | Reusa provider RSS existente. URL de canal → feed RSS automático. |
| **GitHub Events** | wom:Event, wom:Signal, wom:Artifact | Issues, PRs, stars, releases como sinais. Dev feed. REST API pública. |

### Descartados
- **Reddit** — API fechada desde 2023, cobra caro, termos proíbem reprodução
- Substituído por **Lemmy** (ActivityPub, já coberto por Mastodon provider) + **Hacker News**

### Futuro (exploratório)

**Usenet/NNTP** — Rede de discussão descentralizada (1980, RFC 3977). Protocolo text-based simples (~200 linhas para implementar). Valor para Wirc:
- **Threading nativo:** header `References` = árvore de respostas. Nem flat (IRC) nem algorítmico (Reddit). Threading puro baseado em dados.
- **Cross-posting:** um post existe em N grupos simultaneamente (= WOMObject com múltiplos bindings).
- **Message-ID global:** ID único por artigo, mapeamento 1:1 para `urn:wom:object:`.
- **Retenção distribuída:** nenhum server precisa guardar tudo. Rede preserva coletivamente (mesmo modelo de Nostr relays).
- **Servers disponíveis:** eternal-september.org (grátis), ou providers pagos (~$5/mês).
- **Mapeamento WOM:** Article → `wom:Post` (ou `wom:Comment` se tem References), com `relationships: [inReplyTo]` para threading.
- **Esforço estimado:** ~200-300 linhas (protocolo text-based como IRC).

**Wikimedia (Wikidata + Wikipedia + Commons + Wikivoyage)** — Não é feed, é **oráculo de enriquecimento**. Query on-demand para dar contexto, fotos, dados estruturados e desambiguação a WOMs de outros providers.

Casos de uso:
- **Wikidata:** Enriquecer entidades automaticamente (WOM menciona "Honda CG 160" → busca propriedades: fabricante, cilindrada, peso, potência).
- **Wikipedia:** Contexto sob demanda ("O que é isso?" → resumo inline sem sair do feed).
- **Commons:** Thumbnails automáticas para lugares/entidades (90M+ arquivos CC).
- **Wikivoyage:** Info de destinos para rotas (como chegar, o que ver, segurança, clima).
- **Wikidata disambiguação:** "Victoria" qual? Resolve por contexto (geohash, tópico).

Diferença dos outros providers:
| Provider normal | Wikimedia |
|---|---|
| Stream contínuo | Query on-demand |
| Produz WOMs novos | Enriquece WOMs existentes |
| Usuário se inscreve | Automático (background) |
| Real-time | Cache pesado (dados mudam raramente) |

Viabilidade: ✅ API grátis, sem auth, rate limit generoso, CC0/CC-BY-SA, ~100-150 linhas.

---

## Captura de Conteúdo (Como feeds entram no Wirc)

### Share Sheet (iOS — prioridade máxima)
Qualquer app → Share → Wirc. Funciona para YouTube, blogs, podcasts, qualquer URL. Um único Share Extension para todos os providers. 2 toques, zero digitação.

### Clipboard Detection (passivo)
Ao abrir o Wirc, detecta URL no clipboard → sugere follow/bookmark. Banner discreto.

### Safari Web Extension (browser bookmarks)
Botão 🔖 no Safari → envia para Wirc como bookmark. Mesma extensão funciona em iOS + macOS. Bookmark chega como WOMObject signal.

---

## Modelo Social: Seguir Pessoa = Herdar Universo

### Adicionar contato importa tudo automaticamente
Ao adicionar João como contato, Wirc coleta tudo que ele deixou público:
- Canais YouTube que segue → viram feeds
- Feeds RSS dele → viram feeds
- Perfis Mastodon → posts dele aparecem
- Listas curadas → disponíveis
- Nostr follows → expandem grafo

Tudo taggeado com provenance: "via João".

### Feed sem filtro
- Cronológico puro (sem algoritmo)
- Cada card mostra: conteúdo + fonte original + **caminho** (por quem chegou)
- Sem dedup: se João e Ana trouxeram o mesmo link, mostra 2x (isso é signal)

### Listas curadas como WOM objects
Quem curou uma lista grande é um editor. A lista dele é conteúdo valioso:
- Tipo: `wom:Collection` + `wom:Recommendation`
- Assinada pelo curador (provenance.actor)
- Importável com 1 toque ("Seguir todos")
- Propaga pelo trust graph

---

## Discovery Transitivo (Amigos de Amigos)

### Pedir listas dos amigos de João
Meu Wirc pede ao Wirc do João → João consulta localmente → retorna listas públicas dos amigos dele.

```
Profundidade 0: Meus feeds diretos
Profundidade 1: via João (amigo direto)
Profundidade 2: via João → Carlos (amigo do amigo)
```

Cada hop: visível no card, confiança implícita diminui com distância.

### Privacidade: quem controla
- "Minha lista é pública" → cada pessoa decide (governance.sharing)
- "Aceito propagar listas dos meus amigos" → João pode desligar
- "Esse amigo não quer ser propagado" → amigo marcou privado → nunca sai
- Ninguém é exposto sem consentimento

---

## Bookmarks

### Bookmark = signal sobre conteúdo (não cópia)
```
WOMObject signal:
  type: ["wom:Signal"]
  signalType: "bookmarked"
  object: → aponta para conteúdo original
  attributedTo: → eu
  governance: { sharing: "friends_only" }
```

### Bookmarks como feed social
- Minhas bookmarks públicas viram coleção curada automática
- Amigos veem o que salvei como um feed: "Wilson salvou: ..."
- Coincidência social: "3 amigos salvaram esse link" = forte signal sem algoritmo

### Bookmarks de browser
- **Share Sheet** — qualquer URL compartilhada vira bookmark no Wirc
- **Safari Web Extension** — botão 🔖 no browser envia direto para Wirc
- Wirc enriquece URL crua: fetch og:title, og:description, og:image → card rico

### Governança de bookmarks
| Default | Opções |
|---------|--------|
| `local_only` | Privado (maioria) |
| `friends_only` | Só amigos veem |
| `public` | Qualquer seguidor vê |
| Override individual | Sim, por bookmark |

---

## Princípios Confirmados

1. **Seguir pessoa > seguir feed.** Feeds vêm das pessoas, não de URLs.
2. **Caminho sempre visível.** "via João → Carlos → YouTube" nunca fica escondido.
3. **Trust graph É o algoritmo.** Sem ML, sem black box. Coincidência social = recomendação.
4. **Zero friction.** Share Sheet para entrar, 1 toque para importar listas, automático para propagar.
5. **Local-first.** Tudo funciona sem servidor. Nostr/mesh para sync, não como dependência.
6. **Consentimento em cada camada.** Ninguém é propagado sem marcar público. Ninguém é exposto sem opt-in.

---

## Comunicação Wirc-to-Wirc (sem servidor)

### Canal principal: IRC
IRC é o backbone de comunicação entre Wircs. Provider já implementado, protocolo trivial de operar, sem gatekeepers, replicável por qualquer comunidade com $5/mês.

```
Cada comunidade/clube pode ter seu IRC:
  irc.brazoocas.club (Ergo IRCd, 1 Docker container, 1 DNS record)

Canais:
  #sync     → Wircs trocam WOMObjects (JSON assinado)
  #public   → feed público do grupo
  #riders   → chat normal entre membros
```

### Por que IRC e não email/Nostr como backbone?

| | IRC | Email | Nostr |
|--|---|---|---|
| Provider no Wirc | ✅ Já implementado | ❌ Precisaria criar | ✅ Próximo |
| Setup servidor | 1 binário + 1 DNS record | Docker + MX + SPF + DKIM + DMARC | 1 binário + 1 DNS |
| Funciona dia 1 | ✅ Sim | ❌ Deliverability demora semanas | ✅ Sim |
| Gatekeepers | Nenhum | Gmail/Outlook bloqueiam | Nenhum |
| Replicável | Trivial | Médio-difícil | Trivial |
| Custo | $5/mês | $5-10/mês | $5/mês |

### Segurança: IRC é tubo burro, WOM é a confiança
O Wirc não confia no IRC. A segurança vem do WOM:
- **Identidade:** WOMObject assinado com Ed25519 — verificável sem confiar no servidor
- **Integridade:** Se alguém altera o JSON, assinatura invalida
- **Confidencialidade (fase 5):** Payload encriptado antes de enviar ao IRC — servidor vê gibberish
- **Regra:** Nunca confie no transporte. Confie na assinatura.

### Outros canais (complementares, não primários)

| Canal | Papel | Quando |
|-------|-------|--------|
| **BLE/MultipeerKit** | Presença, sync proximity | Quando perto fisicamente |
| **Nostr** | Sync assíncrono, publicação pública | Quando ambos têm relays em comum |
| **Email (newsletter)** | Distribuição para fora, onboarding | Feature futura — newsletter para quem não tem Wirc |

### Hierarquia de transporte
```
1. IRC (backbone principal, sempre disponível, já implementado)
2. BLE/MultipeerKit (presencial, instantâneo)
3. Nostr (assíncrono, relay público, fase próxima)
4. Email newsletter (distribuição outbound, fase futura)
```

---

## Modo Aberto (BLE Mesh Ambient)

### Conceito
Wirc pode manter escuta BLE contínua, trocando WOMs com qualquer outro Wirc por perto — sem grupo, sem seguir ninguém, sem internet. O phone vira nó de uma rede mesh social ambient.

### Como funciona
```
Phone com Modo Aberto:
  - Advertising: "Sou um Wirc, tenho WOMs para trocar"
  - Scanning: "Quem mais é Wirc aqui?"
  - Handshake automático com qualquer outro Wirc detectado
  - Troca de WOMs conforme governance de cada um
```

### O que propaga no Modo Aberto

| Propaga | Exemplo |
|---------|---------|
| WircCard (identidade pública) | Nickname, interesses, clubes |
| Bookmarks `sharing: public` | Links que salvei publicamente |
| Alertas/hazards da região | "Acidente na rua X" |
| Event beacons | "Meetup de devs amanhã aqui" |
| Listas curadas `sharing: public` | "Meus 20 canais favoritos" |
| Pacotes em trânsito (carteiro) | WOMs de outros para entregar adiante |

### O que NÃO propaga
- Nada `local_only` ou `friends_only` (a menos que receptor seja amigo)
- Mensagens privadas
- Conteúdo de grupos fechados

### Configuração (opt-in)
```
Settings → Modo Aberto:
  [🟢 Ativo]  — trocar WOMs com Wircs por perto
  [⚪ Passivo] — só receber, não anunciar
  [⚫ Fechado] — BLE desligado, sem troca ambient
```

### Cenários
- **Conferência:** 200 Wircs abertos. Todos saem com WircCards e bookmarks públicos de quem estava no salão.
- **Café:** 3 Wircs. Troca silenciosa. Descubro blog que alguém por perto bookmarkou.
- **Metrô:** Carteiro cego. Carregando WOMs que serão entregues quando encontrar o destinatário.
- **Protesto/evento:** Beacons propagam sem internet. Mesh organiza informação localmente.

### Protocolo
Mesmo protocolo WawaMesh (BLE dual-role, pacotes com header, TTL, dedup, flood/relay, fragmentação). A diferença: payload é WOMObject em vez de CompactLocation.

### Implicação
Wirc com Modo Aberto não é só client de feeds — é nó de uma **rede mesh de informação**. Cada phone com Wirc é infraestrutura. A rede cresce com cada instalação. Não precisa de IRC, Nostr, nem internet. Só proximity.

---

## Troca por Aproximação (Proximity Tap)

### Conceito
Aproximar dois phones para trocar WOMs intencionalmente — o equivalente digital de trocar cartões de visita. Sem QR, sem PIN, sem digitar nada. Só aproximar.

### Como funciona (BLE RSSI como trigger)
Dois Wircs com Modo Aberto já se detectam via BLE (~30m). Quando RSSI indica **<1 metro de distância**:
- Trigger especial: "troca intencional" (não é ambient passivo)
- Ambos vibram
- Tela mostra: "📲 Trocar com [João]?" → 1 toque confirma
- Troca completa (cards, listas, follows mútuos)

### Por que não NFC?
Apple bloqueia NFC peer-to-peer no iOS (reservado para Apple Pay). Mas BLE RSSI atinge o mesmo resultado — proximidade extrema como gesto intencional.

### Upgrade: Nearby Interaction (UWB, iPhone 11+)
Chip U1/U2 dá distância com precisão de ~10cm e detecta direção. Trigger ainda mais preciso que RSSI. Funciona como upgrade transparente — se ambos phones têm UWB, usa. Senão, BLE RSSI.

### O que troca no "tap"
| Modo | O que vai |
|------|-----------|
| **Mínimo** (default) | WircCard (nickname, interesses, pubkey) |
| **Social** | Card + bookmarks públicos recentes + listas |
| **Full sync** | Tudo público + início de subscription mútua |

Configurável: "quando alguém se aproxima, compartilho: [só card / card+bookmarks / tudo público]"

### UX
```
Eu e você no café. Aproximamos os phones.
  1. Ambos vibram
  2. "Trocar com João?" [Sim]
  3. Pronto — cards trocados, follows mútuos, listas importadas
  Total: 1 toque. Sem QR. Sem PIN. Sem digitar.
```

### Diferença de Modo Aberto (ambient) vs Tap (intencional)
| | Modo Aberto (ambient) | Proximity Tap |
|--|---|---|
| Range | ~30m | <1m |
| Intenção | Passivo (acontece sem perceber) | Ativo (gesto deliberado) |
| Confirmação | Nenhuma (auto) | 1 toque (vibra + pergunta) |
| O que troca | Só `sharing: public` | Pode incluir `friends_only` (está virando amigo agora) |

---

## Transações Financeiras (Bitcoin/Lightning)

### Princípio
Para o Wirc, uma transação financeira é mais um WOMObject. Não somos wallet. Não temos custódia. O pagamento é um signal como qualquer outro — tem origem, destino, valor, propósito e governance.

### Casos de uso

| Cenário | Gesto |
|---------|-------|
| Gorjeta (zap) | Vi lista incrível do João → "⚡ 500 sats" → 1 toque |
| Curadoria paga | João cobra 1000 sats/mês para lista premium |
| Evento pago | Ride Beacon com inscrição: 5000 sats |
| Marketplace P2P | "Vendo capacete" → pagamento direto, sem plataforma |
| Split de conta | Grupo divide gasolina/almoço |
| Bounty | "Melhor rota SP→Santos ganha 10k sats" |

### Implementação: NIP-47 (Nostr Wallet Connect)
- Usuário conecta wallet Lightning existente (Phoenix, Alby) ao Wirc 1x
- Wirc envia/recebe pagamentos via Nostr relay (já temos)
- Non-custodial (Wirc nunca toca nos fundos)
- Produção: Damus, Amethyst, Primal já usam este padrão

### WOM para transações
```json
{
  "type": ["wom:BusinessEvent", "wom:CommerceSignal"],
  "eventName": "payment_sent",
  "commercial": {
    "value": 500,
    "currency": "SAT",
    "recipient": "did:key:joao",
    "purpose": "zap_recommendation",
    "attribution": { "source": "curated_list", "object": "urn:wom:collection:joao-motos" }
  },
  "governance": { "sharing": "local_only" }
}
```

### Regras
- Tudo funciona sem bitcoin (pagamentos são opt-in)
- Wirc não é wallet (não tem custódia, não guarda chaves de Bitcoin)
- Wirc é canal (mostra botão de pagar, delega para wallet do usuário)
- Transação vira WOMObject local (histórico, auditoria, atribuição)
- UI mostra sats ou moeda local (não BTC — menos intimidante)

---

## Fórum / Marketplace / Classificados Descentralizados

### Princípio: um único modelo para tudo
Fórum, marketplace e classificados são o mesmo WOMObject — a diferença é só o `type` e os campos preenchidos. Mecânica de propagação, threading, signals e discovery é idêntica.

```
Fórum:        type: [wom:Post]          → "Best route to Tofino?"
Marketplace:  type: [wom:Offer, wom:Product] → "Vendo capacete Shoei"
Classificado: type: [wom:Offer]         → "Procuro garupa para domingo"
Evento:       type: [wom:Event]         → "Encontro sábado posto Shell"
```

### Persistência longa
Posts de fórum/marketplace vivem semanas/meses (vs localização que vive segundos):
```
governance: { retention: "30d", sharing: "public" }
```
Conteúdo sobrevive enquanto pelo menos 1 nó na rede o possui. Sem servidor central.

### Threading (replies encadeados)
Replies apontam para o parent via `relationships: [{ type: "inReplyTo", object: "..." }]`. Cada Wirc monta a árvore localmente a partir dos WOMs que possui.

### Lifecycle de um classificado
1. Post criado → propaga por topic tag + geohash + feed de seguidores
2. Pessoas interagem (signals: interested, perguntas)
3. Venda concretizada (pagamento Lightning) → signal "sold" → para de propagar
4. Retention expira → removido dos nós que não interagiram

---

## Interação como Broadcast (propagação social)

### Modelo: cada interação amplifica
```
Eu interajo com um WOM (like, comment, bookmark):
  → Esse WOM passa a fazer parte do MEU feed público
  → Meus seguidores o recebem (com provenance mostrando o caminho)
  → Se eles interagem, seguidores DELES recebem → cascata
```

Não é opt-in por post. É consequência natural de interagir. "Gostei" = "meus amigos veem". Como no mundo real.

### Cadeia de provenance visível
```
"Vendo capacete Shoei"
  Pedro (autor)
  📍 via Ana ❤️ → Carlos 💬 → Wilson ❤️ → Pedro (origem)
```
O caminho completo é visível. Cada receptor sabe como chegou até ele.

### Diferença de repost explícito
| Repost (Mastodon boost) | Interação como broadcast (Wirc) |
|---|---|
| Ação consciente ("quero republicar") | Ação natural ("gostei") |
| 1 hop (meus seguidores) | Cascata (cada interação amplia) |
| Viral controlado | Viral orgânico pelo trust graph |

### Pra marketplace é poderoso
```
Pedro posta "Vendo capacete" → 5 seguidores diretos
  3 likes de amigos → atinge 40-50 pessoas
  1 comment "bom preço!" → atinge 60+
  
Craigslist com alcance viral orgânico.
  Sem pagar boost. Sem algoritmo. Sem plataforma.
  Produto bom ganha alcance porque PESSOAS interagiram.
```

### Qualidade se auto-seleciona
Post bom → interações → propaga → mais gente vê → mais interações.
Post ruim → 0 interações → morre com 5 views.
O "algoritmo" é humano. Trust graph amplifica. Lixo não propaga.

### Controle de propagação
```
Settings → Propagação:
  [🟢 Tudo]     → qualquer interação propaga
  [🟡 Seletivo] → só likes/bookmarks (comments não)
  [⚫ Silencioso] → consumo sem amplificar

Por post: "Interagir sem propagar" (silent like)
```
Default: tudo propaga. Quem quer silêncio desliga.

---

## Espaço e Tempo (Contexto Situacional)

### Princípio
Todo WOM pode ter coordenadas e/ou timestamp. Isso transforma o Wirc de "feed cronológico" para **camada informacional sobre o mundo físico** — descoberta por proximidade espaço-temporal.

### 3 visões sobre os mesmos dados
```
FEED:     "O que há de novo no mundo?" (scroll vertical, cronológico)
MAPA:     "O que há de novo AQUI?" (visão espacial, raio de relevância)
TIMELINE: "O que acontece AGORA / AMANHÃ?" (visão temporal)
```
O WOM não muda. Muda a lente.

### Camadas de tempo

| Camada | Duração | Exemplos | Comportamento |
|--------|---------|----------|---------------|
| Efêmero | Segundos | Presença, localização ao vivo | Sobrescreve anterior |
| Instantâneo | Minutos/horas | Hazard, alerta | Expira rápido |
| Eventual | Dias | Evento, encontro | Relevante no futuro próximo |
| Durável | Semanas/meses | Classificado, oferta | Ativo enquanto não vendido/fechado |
| Permanente | Indefinido | Review, recomendação | Nunca expira, acumula |
| Histórico | Passado | "Em 2020 houve enchente aqui" | Contexto informativo |
| Recorrente | Cíclico | "Toda terça 18h" | Reaparece |

### Camadas de espaço

| Escala | Raio | Exemplos |
|--------|------|----------|
| Aqui (ponto) | <50m | "Mesa livre neste café" |
| Quarteirão | 50-500m | Hazard, evento próximo |
| Bairro | 500m-3km | Classificados locais, meetups |
| Cidade | 3-30km | Marketplace, comunidade |
| Região | 30-300km | Rotas, trilhas, turismo |
| Global | Sem limite | Posts de fórum, artigos |

### Relevância = geometria (não algoritmo)
```
relevance = f(distância_espacial, distância_temporal)

Perto + agora → muito relevante
Perto + amanhã → relevante
Perto + semana passada → pouco (permanente não decai)
Longe + agora → pouco (exceto escala global)
```
Não é algorithmic ranking. É a mesma fórmula que o cérebro usa no mundo real.

### Clustering implícito por espaço-tempo
WOMs que não se referenciam explicitamente mas estão no mesmo local+hora são contextualmente relacionados:
```
"Buraco na Augusta" (📍 hoje 10h)
"Cuidado obra na Augusta" (📍 ontem)
"Augusta tá interditada?" (📍 hoje 9h)
→ 3 WOMs sobre o MESMO CONTEXTO, sem linking explícito. Agrupáveis por geometria.
```

### Eventos como atratores gravitacionais
Um evento futuro puxa outros WOMs para si por proximidade espaço-temporal + topic:
```
"Passeio Serra do Rio — Sábado 7h" (evento)
  ├── "Divide gasolina sábado?" (classificado)
  ├── "Rota sugerida: via Raposo" (post)
  ├── "Radar novo na Anchieta" (hazard na rota)
  ├── "Previsão: chuva após 11h" (informação temporal)
  └── "Quem vai? 🙋" (RSVP)
```

### Lugares como entidades emergentes
Convergência de muitos WOMs no mesmo ponto cria identidade de lugar:
```
"Posto Shell — Av. Brasil km 12":
  - 47 check-ins
  - 12 ride beacons ("saída daqui")
  - 3 reviews
  - 1 hazard
  - 2 classificados

Lugar emerge dos WOMs. Não precisa ser cadastrado.
Google Places sem Google — crowdsource puro.
```

### Rotas como espaço contínuo
Rota é uma polyline, não um ponto. WOMs num raio de 500m da polyline são contextualmente relevantes (hazards na rota, postos ao longo, mirantes, reviews de trechos).

### Estrutura WOM

```json
{
  "location": {
    "type": "point",
    "coordinates": [-23.555, -46.662],
    "radius": 1000,
    "relevanceScale": "city",
    "name": "Av. Paulista"
  },
  "temporal": {
    "type": "eventual",
    "startsAt": "2026-06-22T09:00:00",
    "endsAt": "2026-06-22T12:00:00",
    "expiresAt": "2026-06-22T13:00:00",
    "recurrence": null
  }
}
```

### O resultado
```
Mundo físico (espaço + tempo)
    ↓ WOMs ancorados a coordenadas + timestamps
Camada informacional coletiva
    ↓ Filtrada pelo contexto de cada pessoa
Feed contextual: "O que é relevante para MIM, AQUI, AGORA"
```

Não é "posts sobre comida" (topic). É "posts sobre comida AQUI PERTO + ATIVOS AGORA + propagados por gente que confio" (topic + espaço + tempo + trust graph).

---

## Aplicações de Espaço + Tempo

### 1. Radar comunitário (hazards)
**Viável agora ✅** — Já especificado para Wawa Ride. WOM com location + expiresAt. Propaga por Nostr geohash + BLE mesh. Esforço: já feito.

Riders reportam condições da estrada ao vivo. Confirmações crowd-vote. Expira por categoria (animal=1h, radar=3h, acidente=6h).

### 2. Classificados locais
**Viável agora ✅** — WOM type Offer + location (radius: cidade) + retention 30d. Propaga por IRC #marketplace + Nostr geohash + interação de amigos. ~20 linhas de adapter.

Comprador não busca — classificado encontra ele pela proximidade. Like de amigos amplifica alcance organicamente.

### 3. Notas no espaço (dead drops)
**Viável agora ✅** — WOM com location (ponto exato) + retention permanente. Descobre via BLE (está no local) ou Nostr geohash (planejando ir). ~10 linhas (WOM normal com location preenchido).

Mensagens ancoradas a um local. Quem passa ali encontra. Acumula com o tempo, cria história do lugar.

### 4. Evento com ecossistema
**Viável agora ✅** — WOM type Event com startsAt/endsAt. Replies e signals se agrupam por inReplyTo. Evento como atrator gravitacional: puxa classificados, hazards, RSVPs, informações. ~30 linhas de UI de agrupamento.

### 5. Memória coletiva de rota
**Viável agora ✅** — WOMs permanentes com location ao longo de polyline. Acumulam no Nostr. Wirc filtra por corredor (500m da rota). Crowdsource cumulativo: postos, mirantes, perigos, reviews de trechos.

### 6. Classificado que encontra o comprador
**Parcialmente viável ⚠️** — Funciona se usuário tem geohash subscription ativa (Nostr). Não é push (iOS não permite push sem servidor). É pull quando abre o app ou está com Modo Aberto (BLE detecta na proximidade).

Bloqueio: depende do receptor ter Wirc aberto ou subscription ativa na região.

### 7. Serendipidade (descoberta por coincidência espacial)
**Parcialmente viável ⚠️** — BLE detecta frequência de encontros com mesmo Wirc. Tecnicamente possível mas privacidade delicada: precisa persistir histórico de detecção. Opt-in com consentimento claro.

Ideia: "Alguém que frequenta os mesmos lugares está aqui. Interesses em comum: motorcycles, tech." Assistência à serendipidade, não surveillance.

### 8. Mapa contextual "o que há aqui agora?"
**Parcialmente viável ⚠️** — A feature é poderosa mas depende de massa crítica. Com 10 usuários numa cidade, mapa fica vazio. Funciona bem em eventos/concentrações onde há densidade. Cresce naturalmente com base de usuários.

### 9. Time capsule (arqueologia social)
**Parcialmente viável ⚠️** — Grupo faz passeio anual. Cada edição deixa WOMs (GPX, fotos, notas). Depende de retenção longa — relays Nostr podem apagar. Funciona se participantes guardam localmente e re-publicam. Ou se comunidade tem IRC server próprio com logs.

### Resumo de viabilidade

| Aplicação | Viável? | Depende de |
|-----------|---------|-----------|
| Hazards/radar | ✅ Agora | Nada novo — já temos tudo |
| Classificados locais | ✅ Agora | Nostr geohash + IRC topic |
| Notas no espaço | ✅ Agora | WOM com location, Nostr persiste |
| Evento + ecossistema | ✅ Agora | Threading (inReplyTo), UI de agrupamento |
| Memória de rota | ✅ Agora | WOMs permanentes + filtro por corredor |
| Classificado que te acha | ⚠️ Parcial | Usuário com app aberto ou subscription ativa |
| Serendipidade espacial | ⚠️ Parcial | Privacidade + persistência de encontros |
| Mapa contextual | ⚠️ Parcial | Massa crítica de usuários na região |
| Time capsule | ⚠️ Parcial | Retenção longa (relay ou local) |

---

## Multi-Canal: WOM Único, Todos os Canais

### Princípio: canais são on-ramps, não silos
Conteúdo não vive DENTRO de um canal. O WOM é o objeto. Canais são caminhos de entrada e saída. Qualquer canal que tocar o WOM o torna acessível a mais gente. Nenhum canal é dono.

### Todos os canais simultâneos

| Canal | Como propaga classificados/fórum/eventos | Força | Fraqueza |
|-------|------------------------------------------|-------|----------|
| IRC #canal | `#marketplace-victoria` | Comunidade fixa, logs, moderação | Precisa server + conhecer o canal |
| Nostr (tags + geohash) | Tags temáticas + geolocalização | Global, qualquer relay, sem cadastro | Retenção varia por relay |
| BLE Modo Aberto | Propaga para quem está perto | Zero internet, instantâneo | Alcance ~30m |
| Cascata social (feed) | Like/comment → amigos veem | Alcance orgânico, confiança | Depende de interação |
| QR físico | Mural do posto/oficina → link para WOM | Mundo real, qualquer phone | One-shot |
| Email newsletter | Digest semanal | Alcança quem não tem Wirc | Fase futura |

### Publicação: todos os canais ao mesmo tempo
```
Pedro posta "Vendo capacete":
  → IRC: #marketplace-victoria
  → Nostr: geohash Victoria + tag "marketplace"
  → BLE: quem está por perto
  → Feed: amigos veem; se interagem, cascata
  Mesmo WOM, todos os canais simultâneos.
```

### Descoberta: qualquer canal serve
Receptor não precisa estar no mesmo canal que o autor:
- Autor publica no IRC. Receptor descobre via Nostr geohash.
- Autor publica via BLE. Alguém com internet republica no Nostr → global.
- Autor cola QR. Alguém escaneia → WOM entra no Wirc → se interage, propaga digital.

### Dedup garante: mesmo WOM, 1 processamento
Receber por 2 canais = mesmo ID WOM = processa 1x. Redundância é feature.

### IRC é conveniência, não dependência
Canal IRC é útil para comunidade fixa com moderação e logs. Mas NÃO é obrigatório. Nostr + BLE + cascata social funciona sem IRC. Cada canal é opcional — quanto mais ativos, maior o alcance.

---

## Salas Geolocalizadas (Auto-Join por Proximidade)

### Conceito
Canais IRC mapeados a regiões. Wirc monitora posição e faz JOIN/PART automático conforme o usuário se move.

```
Andando de moto por Victoria:
  Entrei em Downtown → auto-join #victoria-downtown
  Passei para Oak Bay → part #downtown, join #oakbay
  Saí da cidade → part tudo, join #highway-bc-1
```

### Níveis de sala simultâneos

| Nível | Geohash precision | Área | Exemplo |
|-------|-------------------|------|---------|
| Micro | 7 (~150m) | Quarteirão | #posto-shell-km12 |
| Local | 6 (~1.2km) | Bairro | #victoria-downtown |
| Cidade | 5 (~5km) | Zona | #victoria |
| Região | 4 (~39km) | Metrópole | #vancouver-metro |

O Wirc pode estar em múltiplos níveis ao mesmo tempo. Usuário silencia os que não quer.

### Highway channels (canais de rota)
Canais mapeados a polylines. Auto-join quando GPS indica que estou naquela rota.
```
#br-101-sul → polyline SP-Curitiba
#highway-1-bc → Trans-Canada
Chat com quem está na mesma estrada agora.
```

### Criação de salas
- **Automática:** Server cria canal quando primeiro JOIN por geohash. Sem custo.
- **Curada:** Comunidade nomeia canais com significado (vs geohash críptico).

### Chat → WOM permanente
Mensagem útil no chat pode ser "promovida" a WOM permanente com 1 toque:
```
<rider_joao> buraco na esquina Broad com Fort
  → [📌 Promover para Hazard] → vira WOM permanente, propaga para Nostr/BLE/etc.
```

### Privacidade
- Auto-join é opt-in (setting: Ativo / Perguntar / Desligado)
- Nicks podem ser anônimos por canal geo
- Server com logs mínimos ou sem logs

---

## Briefing Automático ao Entrar na Sala

### O que o usuário vê ao fazer JOIN
```
📋 BRIEFING — Victoria Downtown

📌 FIXO: "Centro comercial. Motos na Yates St. Zona 30km/h."
⚡ AGORA: ⚠️ Obra Douglas St — desvio Blanshard (2h)
         🌤️ 18°C, vento fraco
         👥 3 riders ativos
📅 PRÓXIMO: Meetup Sáb 10h JJ Bean (2 dias)
📊 STATS: 12 riders passaram hoje, 1 hazard ativo, 3 classificados
```

### Três fontes de dados (todas possíveis, complementares)

**A. Bot IRC no server (mais poderoso)**
- Detecta JOIN
- Consulta WOMStore central ou API
- Envia NOTICE com briefing completo
- Pode integrar dados externos (clima, trânsito)

**B. Wirc client local (sem bot, sem infra)**
- Ao JOIN, consulta WOMs locais que já possui para aquela região
- Monta briefing localmente
- Não precisa de bot nem server especial
- Limitado ao que o client já sabe

**C. Híbrido (melhor dos dois)**
- TOPIC + Pinned WOMs = dados fixos (server-side)
- Client enriches com WOMs locais dinâmicos
- Bot opcional adiciona dados externos (clima, contagens globais)

### As três opções coexistem
Não é escolher uma. É cascata: client mostra o que sabe localmente. Se tem bot, adiciona mais. Se tem TOPIC/pinned, complementa. Resultado final é a soma.

### Dados fixos
- **TOPIC IRC:** Descrição editável pelos ops do canal ("Motos na Yates St. Posto Shell na Douglas.")
- **Pinned WOMs:** WOMObjects permanentes fixados ao canal (estruturados, pesquisáveis)

### Dados dinâmicos (computados)

| Dado | Fonte | Refresh |
|------|-------|---------|
| Hazards ativos | WOMs na região, não expirados | A cada JOIN + timer |
| Eventos próximos | WOMs Event, startsAt < 7 dias | A cada JOIN |
| Classificados | WOMs Offer ativos | A cada JOIN |
| Riders agora | IRC NAMES (count no canal) | Real-time |
| Stats (passaram hoje) | JOIN count local | Calculado |
| Clima | API externa ou WOM de weather | Periódico |
| Condição estrada | Último hazard resolvido/ativo | Sob demanda |

---

## Bot = Wirc do Dono (Estabelecimento como Sala)

### Modelo
O dono de um negócio local roda Wirc no iPhone/Mac do balcão. Esse Wirc É o bot da sala — não é infra separada. Criou canal com geohash do estabelecimento (raio ~100m). Quando alguém passa e faz auto-join, recebe briefing servido pelo Wirc do dono.

### Exemplo: consultório de dentista
```
Passante com Modo Aberto caminha pela Commercial Drive:
  → Geohash match → auto-join #drsilva-dental
  → Wirc do Dr. Silva detecta JOIN → envia briefing:

  🦷 Dr. Silva — Clínica Odontológica
  📌 Commercial Drive, 1847 — 2º andar
  🕐 Seg-Sex 8-18, Sáb 8-12
  ⚡ Horário disponível hoje: 15:30
  📋 Espera: ~10min
  💰 Limpeza: $120 | Consulta: $80
  📅 Promoção clareamento Jun: $299
```

### Quem serve: o device do dono
| Aspecto | Servidor tradicional | Wirc do dono |
|---------|---------------------|--------------|
| Onde roda | Cloud/VPS | iPhone/Mac no balcão |
| Custo | $5-50/mês | $0 (device que já tem) |
| Online quando | 24/7 | Quando estabelecimento aberto (natural) |
| Dados dinâmicos | API | Integra Calendário/Lembretes iOS |

### Configuração do dono
```
Settings → Meu Estabelecimento:
  Nome, endereço, horário, geofence (raio)
  Briefing fixo: preços, serviços
  Briefing dinâmico: [✅] próximo horário (Calendário iOS)
                     [✅] tempo de espera (manual)
                     [✅] promoções ativas
  Modo: [🟢 Ativo] auto-responde | [⚪ Passivo] só briefing
```

### Qualquer negócio local
| Negócio | Briefing dinâmico | Raio geofence |
|---------|-------------------|---------------|
| Dentista | Horário livre, espera, preços | ~100m |
| Restaurante | Mesa, prato do dia, espera | ~50m |
| Oficina moto | Serviços, tempo, peças | ~200m |
| Loja gear | Promoções, novidades | ~100m |
| Camping | Vagas, preço, amenidades | ~500m |
| Posto | Preço combustível, serviços | ~200m |

### Interação bidirecional
Visitante pode perguntar. Dono responde:
- **Manual** (dono lê e responde pelo Wirc)
- **Automatizado** (respostas pré-programadas)
- **IA** (agente Virk consulta calendário + regras)

### Fluxo completo: briefing → agendamento → pagamento
```
Visitante entra na sala geo
  → Recebe briefing
  → Pergunta "tem horário amanhã?"
  → Bot responde "9:30 e 11:00"
  → Visitante escolhe → WOM tipo wom:Offer ($80)
  → Paga sinal via Lightning
  → WOM tipo wom:Event (agendamento confirmado)
  → Lembrete no dia
```
Do descoberta → conversa → transação. Tudo no Wirc. Sem app do dentista. Sem marketplace. Sem taxa de plataforma.

---

## Modo Full Mesh (Comunicação Anônima sem Internet)

### Cenário
Milhares de pessoas numa manifestação. Internet cortada ou monitorada. Pessoas querem se comunicar sem se identificar, sem deixar rastro, sem servidor.

### Como funciona
Wirc com Modo Aberto em BLE mesh puro. Sem internet, sem IRC, sem Nostr. Cada phone é um nó anônimo indistinguível.

### Identidade: nenhuma
| Campo WOM normal | Na manifestação |
|------------------|-----------------|
| `attributedTo` | Omitido (null) |
| `proof/signature` | Omitido (sem prova de autoria) |
| PeerID | Randomizado a cada 60 segundos |

WOM viaja sem autor. Quem lê não sabe quem escreveu. Quem retransmite não sabe de onde veio.

### O que circula
```
⚠️ "Polícia avançando pela Rua X — vão pela Y" (anônimo, efêmero)
📢 "Água e socorro na praça central, tenda azul" (anônimo, location)
📍 "Ponto de encontro se dispersar: estação Z" (anônimo, permanente)
🚨 "Pessoa ferida cruzamento A com B" (anônimo, urgente)
```

### Modo Full Mesh (preset)
```
Settings → Modo Full Mesh:
  ✅ PeerID randomiza a cada 60s
  ✅ Sem logs locais (nada salvo)
  ✅ Sem bindings (IRC/Nostr desconectados)
  ✅ Só BLE mesh (zero internet)
  ✅ WOMs sem attributedTo/proof
  ✅ Wipe automático ao sair do modo
```

### Se phone é apreendido
Nada para encontrar:
- WOMs da sessão: apagados (wipe ao desativar modo)
- Logs BLE: nunca gravou
- PeerID: era random, já rotou dezenas de vezes
- iOS com passcode = disco encriptado

### Verificação sem identidade
Sem assinatura, qualquer um pode enviar desinformação. Abordagem:
- **Crowd confirmation:** mesmo WOM de N phones independentes = mais confiável
- **Nenhuma formal:** contexto presencial é a verificação humana. Info falsa é contra-atacada por mais testemunhas com info verdadeira.

### O que funciona neste modo
- BLE mesh flood (sem internet, local)
- Alertas/hazards propagam rápido
- Anonimato total (ninguém rastreável)
- Sem persistência (nada para forensics)
- Resistente a censura (sem servidor para derrubar)

### O que NÃO funciona
- Trust graph (sem identidade)
- Cascata social (sem grafo)
- Assinaturas/provas
- Pagamentos
- Nostr/IRC (internet cortada)

### Princípio
A mesma tecnologia que mostra riders no mapa aqui protege manifestantes. O protocolo é neutro. Não julga o uso.

---

## Segurança de Menores (Canais Geo em Espaços Públicos)

### Cenário
Adolescentes num canal geo do shopping (#divertilandia). Conversam via Modo Aberto. Quão protegidos estão?

### Proteções nativas da arquitetura
| Proteção | Eficácia |
|----------|----------|
| Geofence real — precisa estar fisicamente no local para entrar | ✅ Forte (predador remoto NÃO entra) |
| Sem perfil pesquisável (não tem "buscar por idade/gênero") | ✅ Forte |
| Sem DM para desconhecidos (só com Proximity Tap mútuo bidirecional) | ✅ Forte |
| Mensagens efêmeras (não persistem, sem histórico para stalkear) | ✅ Moderado |
| Sem foto/idade/escola obrigatórios (só nickname) | ✅ Moderado |

### Comparação com redes tradicionais
| Ameaça | Instagram/TikTok | Wirc canal geo |
|--------|------------------|----------------|
| Predador remoto (outro país/cidade) | ⚠️ ALTO | ✅ IMPOSSÍVEL (geofence) |
| Grooming por meses (DMs, follow) | ⚠️ ALTO | ✅ DIFÍCIL (efêmero, sem follow) |
| Catfishing (perfil falso elaborado) | ⚠️ ALTO | ✅ IMPROVÁVEL (sem perfil) |
| Discovery por idade/escola | ⚠️ ALTO | ✅ IMPOSSÍVEL (sem esses dados) |

### Vulnerabilidade real: predador físicamente presente
Adulto no mesmo shopping entra no canal como qualquer outro. É o mesmo risco de qualquer espaço público — o Wirc não cria nem elimina esse risco. Digitaliza interação que já aconteceria presencialmente.

### Mitigações adicionais possíveis
| Medida | Como |
|--------|------|
| Moderação por estabelecimento | Bot do shopping monitora canal |
| Cooldown para novos | Só lê por 5min antes de falar |
| Report anônimo | Sinalizar para moderador |
| Parental control (opt-in) | Teen mode: sem Tap com desconhecidos, DM bloqueado |
| Geofence timer | Canal só funciona em horário comercial |

### Princípios declarados
1. Wirc não coleta idade/gênero/escola — não pode ser explorado para targeting
2. DMs exigem consentimento mútuo (Proximity Tap bidirecional)
3. Canais geo = espaço público — presença física é pré-requisito
4. Modo Parental possível (restrições opt-in pelos pais)
5. Moderação de canal possível (bot do estabelecimento)
6. Significativamente mais seguro que redes sociais tradicionais para o vetor principal (acesso remoto + perfil + DM aberto)

### Infra replicável por comunidade
Qualquer grupo pode subir um servidor IRC para seu Wirc:
- 1 VPS ($5/mês) + Docker + Ergo IRCd
- 1 A record no DNS
- Funciona imediatamente, sem aquecer reputação
- Membros configuram `irc.seugrupo.com` no Wirc → sync automático

---

## Email (Fase Futura — Newsletter/Distribuição)

### Papel do email no Wirc
Email não é canal de sync. É canal de **distribuição para fora** — newsletter para quem não tem Wirc.

### Como funciona (quando implementado)
- Cada usuário Wirc é uma newsletter automática
- Subscribers sem Wirc recebem digest HTML bonito por email
- Subscribers com Wirc: email inclui `application/vnd.wirc+json` parseável
- Zero config para enviar (usa iOS Mail compose)

### Email dual-purpose (humano + máquina)
```
Content-Type: multipart/alternative
  ├── text/html → Newsletter legível (links, títulos, thumbnails)
  └── application/vnd.wirc+json → WOMObjects parseáveis pelo Wirc
```

### Por que é fase futura (não MVP)
- Friction de config IMAP no app
- Deliverability se servidor próprio
- IRC resolve sync entre Wircs sem esses problemas
- Email brilha para alcançar quem está FORA do ecossistema Wirc

---

## Feed de Pessoa

### Cada usuário Wirc É um feed
Não existe diferença estrutural entre "seguir canal YouTube" e "seguir João". Ambos produzem WOMObjects no meu feed cronológico.

### O que é público vs privado por default

| Atividade | Default | Propaga no feed |
|-----------|---------|-----------------|
| Bookmark | `friends_only` | Sim (para amigos) |
| Follow/subscribe | `public` | Sim |
| Reação (like/recommend) | `public` | Sim |
| Lista compartilhada | `public` | Sim |
| Post (Mastodon, Nostr) | `public` | Sim |
| **Mensagem IRC/DM** | `local_only` | **Não** (privado por default) |
| **Conversa de grupo** | `local_only` | **Não** |

Messaging é privado. Curation é pública. O usuário pode mudar ambos, mas defaults protegem.

### Link compartilhado ≠ Feed compartilhado
Compartilhar um artigo = bookmark (signal sobre aquele item).
Wirc detecta se o link faz parte de um feed (via `<link rel="alternate">` no HTML) e pergunta: "Quer seguir este feed?"

Link e feed são objetos distintos. Um é signal momentâneo. O outro é commit contínuo.

---

## Princípios Confirmados

1. **Seguir pessoa > seguir feed.** Feeds vêm das pessoas, não de URLs.
2. **Caminho sempre visível.** "via João → Carlos → YouTube" nunca fica escondido.
3. **Trust graph É o algoritmo.** Sem ML, sem black box. Coincidência social = recomendação.
4. **Zero friction.** Share Sheet para entrar, 1 toque para importar listas, automático para propagar.
5. **Local-first.** Tudo funciona sem servidor. Nostr/mesh/email para sync, não como dependência.
6. **Consentimento em cada camada.** Ninguém é propagado sem marcar público. Ninguém é exposto sem opt-in.
7. **Cada pessoa é um feed.** Atividade pública = conteúdo para quem segue.
8. **Email é publisher universal.** Todo Wirc é uma newsletter sem plataforma.
