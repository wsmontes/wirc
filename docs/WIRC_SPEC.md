# Wirc — Especificação de Produto (2026-06-18)

---

## 1. Visão

O Wirc é um **client social local-first, multi-protocolo**, onde seguir uma pessoa significa herdar o universo informacional dela. Cada interação amplifica conteúdo pela rede de confiança. Sem servidor central, sem algoritmo, sem plataforma.

### Princípios

1. **Seguir pessoa > seguir feed.** Feeds vêm das pessoas, não de URLs.
2. **Caminho sempre visível.** "via João → Carlos → YouTube" nunca fica escondido.
3. **Trust graph É o algoritmo.** Coincidência social = recomendação. Sem ML, sem black box.
4. **Zero friction.** Share Sheet para entrar, 1 toque para importar, automático para propagar.
5. **Local-first.** Tudo funciona sem servidor. IRC/Nostr/mesh para sync, não como dependência.
6. **Consentimento em cada camada.** Ninguém é propagado sem opt-in.
7. **Cada pessoa é um feed.** Atividade pública = conteúdo para quem segue.
8. **Canais são on-ramps, não silos.** WOM é o objeto. Transporte é substituível.
9. **O protocolo é neutro.** A mesma tecnologia serve riders, comerciantes e manifestantes.

---

## 2. Providers (Fontes de Dados)

### Implementados
| Provider | WOM types | Natureza |
|----------|-----------|----------|
| **IRC** | wom:Message | Stream (real-time, presença) |
| **RSS** | wom:Post | Pull (periódico) |
| **Mastodon** (ActivityPub) | wom:Post, wom:Reaction, wom:Follow | Stream (federado) |

### Aprovados (próximos)
| Provider | WOM types | Esforço |
|----------|-----------|---------|
| **Nostr** | wom:Post, wom:Signal, wom:Reaction | ~200 linhas |
| **Bluesky** (AT Protocol) | wom:Post, wom:Follow, wom:Collection | ~300 linhas |
| **Hacker News** | wom:Post, wom:Comment | ~80 linhas |
| **YouTube** (via RSS) | wom:Post (video) | ~30 linhas (reuso RSS) |
| **GitHub Events** | wom:Event, wom:Signal | ~100 linhas |

### Exploratórios
| Provider | Diferencial |
|----------|------------|
| **Usenet/NNTP** | Threading nativo (References header), cross-posting, Message-ID global. ~200 linhas. |
| **Wikimedia** | Oráculo de enriquecimento (não feed). Wikidata para entidades, Wikipedia para contexto, Commons para imagens, Wikivoyage para rotas. Query on-demand, cache pesado. ~100 linhas. |

### Descartados
- **Reddit** — API fechada (2023), cobra caro, termos proíbem reprodução. Substituído por Lemmy (ActivityPub) + Hacker News.

---

## 3. Captura de Conteúdo

| Método | Plataforma | Descrição |
|--------|-----------|-----------|
| **Share Sheet** | iOS | Qualquer URL de qualquer app → Wirc. Um único extension para tudo. |
| **Clipboard Detection** | iOS | Detecta URL ao abrir app → sugere follow/bookmark. |
| **Safari Web Extension** | iOS + macOS | Botão 🔖 no browser → bookmark no Wirc. |
| **Feed discovery** | Automático | URL compartilhada → Wirc detecta `<link rel="alternate">` → sugere follow do feed. |

---

## 4. Modelo Social

### Seguir pessoa = importar universo
Ao adicionar contato, Wirc coleta automaticamente tudo que ele publicou:
- Canais YouTube, feeds RSS, perfis Mastodon, follows Nostr, listas curadas
- Tudo taggeado: "via João" (provenance.actor)
- Incremental (stream, não bulk download)

### Feed
- Cronológico puro (sem algoritmo)
- Cada card: conteúdo + fonte original + caminho completo ("via quem chegou")
- Sem dedup: mesmo link via 2 pessoas = 2 cards (isso é signal de relevância)

### Listas curadas
- Quem curou lista grande é editor. Lista = `wom:Collection` + `wom:Recommendation`
- Importável com 1 toque ("Seguir todos")
- Propaga pelo trust graph

### Discovery transitivo
- Pedir listas dos amigos de João → João consulta amigos → retorna listas públicas
- Cada hop visível no card (profundidade 0, 1, 2...)
- Privacidade: só propaga o que cada pessoa marcou como público

### Interação como broadcast
- Like/comment/bookmark → WOM entra no MEU feed público → meus seguidores recebem
- Cascata: cada interação amplia alcance pela rede de trust
- Default: tudo propaga. Configurável: seletivo ou silencioso.
- Qualidade se auto-seleciona (sem interações = morre, com interações = viraliza)

---

## 5. Bookmarks

- Bookmark = `wom:Signal` (signalType: "bookmarked") apontando para conteúdo (não cópia)
- Sharing configurável: `local_only` (default) / `friends_only` / `public`
- Bookmarks públicas viram feed curado automático para quem segue
- "3 amigos salvaram este link" = forte signal sem algoritmo
- Wirc enriquece URL: fetch og:title, description, image → card rico

---

## 6. Comunicação Wirc-to-Wirc

### Hierarquia de transporte
```
1. IRC — backbone principal (já implementado, trivial operar, replicável $5/mês)
2. BLE/MultipeerKit — presencial (instantâneo, zero internet)
3. Nostr — assíncrono (relay público, fase próxima)
4. Email — distribuição outbound (newsletter, fase futura)
```

### Sync entre Wircs
- Incremental (stream de objetos ~500B, não bulk)
- Catch-up: últimos 50 items ao seguir + paginar passado sob demanda
- Dedup por WOM ID (multi-canal redundante = feature)

### Segurança
- IRC é tubo burro. WOM assinado (Ed25519) é a confiança.
- Identidade: signature no WOMObject, verificável sem confiar no servidor
- Integridade: alteração invalida assinatura
- Confidencialidade (futura): payload encriptado antes de enviar
- **Regra: nunca confie no transporte. Confie na assinatura.**

### Infra replicável por comunidade
- 1 VPS ($5/mês) + Docker + Ergo IRCd + 1 DNS record
- Funciona imediatamente, sem aquecer reputação
- Qualquer clube/grupo/comunidade opera o seu

---

## 7. Feed de Pessoa

### Cada usuário É um feed
Seguir João = subscribe no stream de atividade dele. Mesma mecânica de seguir canal YouTube.

### Público vs privado por default
| Atividade | Default | Propaga? |
|-----------|---------|----------|
| Bookmark | `friends_only` | Sim (amigos) |
| Follow/subscribe | `public` | Sim |
| Reação (like) | `public` | Sim |
| Lista compartilhada | `public` | Sim |
| **Mensagem IRC/DM** | `local_only` | **Não** |
| **Chat de grupo** | `local_only` | **Não** |

Messaging é privado. Curation é pública. Defaults protegem.

---

## 8. Modo Aberto (BLE Mesh Ambient)

### Conceito
Phone mantém BLE ativo, troca WOMs com qualquer Wirc por perto. Sem grupo, sem follow, sem internet. Rede mesh de informação ambient.

### O que propaga
- WircCard (identidade pública)
- Bookmarks/listas `sharing: public`
- Alertas/hazards da região
- Event beacons
- Pacotes em trânsito (carteiro cego)

### O que NÃO propaga
- Nada `local_only` ou `friends_only` (exceto se receptor é amigo)
- Mensagens privadas

### Configuração
- `[🟢 Ativo]` troca com todos | `[⚪ Passivo]` só recebe | `[⚫ Fechado]` BLE off

---

## 9. Proximity Tap (Troca por Aproximação)

### Conceito
Aproximar phones (<1m, BLE RSSI alto) = gesto intencional de troca. Vibra, confirma, troca completa.

### Diferença do Modo Aberto
| | Modo Aberto | Proximity Tap |
|--|---|---|
| Range | ~30m | <1m |
| Intenção | Passiva | Deliberada |
| Confirmação | Automática | 1 toque |
| O que troca | Só `public` | Pode incluir `friends_only` |

### UWB upgrade
iPhone 11+: chip U1/U2 dá precisão ~10cm. Transparente — se ambos têm, usa. Senão, BLE RSSI.

---

## 10. Espaço e Tempo

### Princípio
Todo WOM pode ter coordenadas + timestamp. Habilita: mapa como feed, discovery por proximidade, contexto situacional ("o que é relevante AQUI, AGORA").

### Camadas temporais
Efêmero (segundos) → Instantâneo (horas) → Eventual (dias) → Durável (semanas) → Permanente → Histórico → Recorrente

### Camadas espaciais
Aqui (<50m) → Quarteirão (500m) → Bairro (3km) → Cidade (30km) → Região (300km) → Global

### Relevância = geometria
`relevance = f(distância_espacial, distância_temporal)` — não é algoritmo, é física social.

### Clustering implícito
WOMs no mesmo local+hora são contextualmente relacionados mesmo sem linking explícito.

### Eventos como atratores
Evento futuro puxa WOMs relacionados (offers, hazards, RSVPs, info) por proximidade espaço-temporal.

### Lugares emergentes
Convergência de WOMs num ponto cria identidade de lugar (crowdsource sem cadastro).

---

## 11. Aplicações Espaço-Temporais

| Aplicação | Viável agora? | Descrição |
|-----------|:---:|---|
| Radar comunitário (hazards) | ✅ | Alertas com location + expiração. Crowd-vote confirma. |
| Classificados locais | ✅ | Offer + location + retention 30d. Comprador encontrado por proximidade. |
| Notas no espaço | ✅ | Mensagens ancoradas a local. Quem passa encontra. Acumula história. |
| Evento + ecossistema | ✅ | Replies/offers agrupam ao redor de evento. Atrator gravitacional. |
| Memória de rota | ✅ | WOMs permanentes ao longo de polyline. Crowdsource cumulativo. |
| Classificado que te acha | ⚠️ | Precisa app aberto ou subscription ativa. Não é push (iOS). |
| Serendipidade espacial | ⚠️ | Frequência de encontros BLE. Privacidade delicada. |
| Mapa contextual | ⚠️ | Depende de massa crítica de usuários. |
| Time capsule | ⚠️ | Retenção longa depende de relay ou local. |

---

## 12. Multi-Canal

### Publicação simultânea
Mesmo WOM vai para todos os canais ativos (IRC + Nostr + BLE + feed). Receptor descobre por qualquer um. Dedup por WOM ID.

### Canais são on-ramps
- Conteúdo não vive dentro de um canal
- Qualquer canal que toca o WOM o torna acessível a mais gente
- IRC é conveniência, não dependência

---

## 13. Salas Geolocalizadas

### Auto-join por posição
Canais IRC mapeados a geohashes. Wirc faz JOIN/PART automático conforme usuário se move. Multi-nível simultâneo (quarteirão + bairro + cidade).

### Highway channels
Canais mapeados a polylines (rotas). Auto-join quando GPS indica que está naquela estrada.

### Chat → WOM permanente
Mensagem útil pode ser "promovida" a WOM permanente (hazard, review, nota) com 1 toque.

---

## 14. Briefing ao Entrar na Sala

### Três fontes coexistentes
- **A. Bot (Wirc do dono/server):** dados dinâmicos ricos (calendário, espera, clima)
- **B. Client local:** monta briefing dos WOMs que já possui para aquela região
- **C. Híbrido:** TOPIC/pinned (fixo) + client enriquece + bot complementa

### Dados exibidos
Fixos (TOPIC/pinned) + Hazards ativos + Eventos próximos + Classificados + Riders presentes + Stats

---

## 15. Estabelecimento como Sala (Bot = Wirc do Dono)

### Modelo
Dono roda Wirc no device do balcão. Criou canal com geohash (~100m). Passantes com Modo Aberto recebem briefing automático.

### Fluxo completo
Descoberta (geofence) → Briefing (preços, horários, disponibilidade) → Conversa (perguntas) → Agendamento → Pagamento (Lightning). Tudo no Wirc. Sem app do negócio. Sem marketplace. Sem taxa.

### Quem serve: o device do dono
$0 de infra. Online quando o estabelecimento está aberto (natural). Integra Calendário iOS.

---

## 16. Transações Financeiras

### Princípio
Pagamento é mais um WOMObject. Wirc é canal, não wallet. Non-custodial.

### Implementação: NIP-47 (Nostr Wallet Connect)
Usuário conecta wallet Lightning existente (Phoenix, Alby) 1x. Wirc delega pagamento.

### Casos de uso
Gorjeta (zap) | Curadoria paga | Evento pago | Marketplace P2P | Split de conta | Bounty

### Regras
- Tudo funciona sem bitcoin (opt-in)
- Wirc nunca tem custódia
- Transação vira WOM local (auditoria, atribuição)

---

## 17. Fórum / Marketplace / Classificados

### Modelo único
Fórum (`wom:Post`), marketplace (`wom:Offer`), classificado (`wom:Offer`), evento (`wom:Event`) = mesmo WOMObject. Diferença é type + campos. Mecânica idêntica.

### Persistência longa
`governance: { retention: "30d" }` — vive enquanto pelo menos 1 nó possui.

### Threading
Replies via `relationships: [inReplyTo]`. Cada Wirc monta árvore localmente.

### Lifecycle
Criado → propaga → interações amplificam → venda/resolução → signal "sold/closed" → para de propagar → expira.

---

## 18. Modo Full Mesh (Comunicação Anônima)

### Quando usar
Internet cortada ou monitorada. Necessidade de comunicação anônima sem rastro.

### Como funciona
- BLE mesh puro (zero internet)
- PeerID randomiza a cada 60s
- WOMs sem attributedTo/proof (sem autoria)
- Sem logs, wipe ao desativar
- Resistente a apreensão (nada para encontrar)

### Verificação
Crowd confirmation (mesmo WOM de N phones = mais confiável). Nenhuma verificação formal — contexto presencial é a validação humana.

---

## 19. Segurança de Menores

### Proteções nativas
- Geofence real (predador remoto não entra)
- Sem perfil pesquisável (não tem "buscar por idade/gênero")
- Sem DM sem consentimento mútuo (Proximity Tap bidirecional)
- Mensagens efêmeras (sem histórico)

### Significativamente mais seguro que redes tradicionais
Elimina vetor principal: acesso remoto + perfil + DM aberto + grooming prolongado.

### Mitigações adicionais possíveis
Moderação por estabelecimento | Cooldown para novos | Report anônimo | Parental control (opt-in) | Geofence timer

---

## 20. Email (Fase Futura)

### Papel
Distribuição para fora — newsletter para quem NÃO tem Wirc. Não é canal de sync (IRC faz isso).

### Formato
Multipart: HTML bonito (legível no Gmail) + JSON WOM (parseável pelo Wirc).

### Cada Wirc é newsletter
Atividade pública vira digest automático. Sem Substack, sem servidor. iOS Mail compose envia.

### Por que é fase futura
IRC resolve sync sem os problemas de deliverability/config de email. Email brilha para alcançar quem está fora do ecossistema.
