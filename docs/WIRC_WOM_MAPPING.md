# Wirc × WOM 0.6 — Mapeamento de Features para Modelo Semântico

**Data:** 2026-06-18  
**Propósito:** Mostrar como cada feature do Wirc (WIRC_SPEC.md) se expressa nativamente em WOM 0.6.

---

## 1. Mapeamento: Features Wirc → Camadas WOM 0.6

| Feature Wirc | Camada WOM 0.6 | Types/Campos Utilizados |
|-------------|----------------|------------------------|
| Feed de pessoa (atividade pública) | Social + Attention | `wom:Post`, `wom:Signal`, `wom:Reaction`, `wom:Follow`, `wom:Collection` |
| Bookmark | Attention | `wom:Signal` (signalType: "bookmarked") + `governance.sharing` |
| Listas curadas | Social | `wom:Collection` + `wom:Recommendation` |
| Trust graph / amigos | Attention | `wom:TrustRelation` (weight, topics, depth) |
| Interação como broadcast | Attention | `wom:Signal` → provenance.path registra cascata |
| Classificado / marketplace | Commercial | `wom:Product` + `wom:Offer` + `wom:BusinessEvent` |
| Hazard / alerta | Core + Attention | `wom:Event` + `wom:Signal` (signalType: "hazard") |
| Ride Beacon / evento aberto | Social + Core | `wom:Event` + `wom:Invite` + `wom:RSVP` |
| Notas no espaço | Core | `wom:Note` (com `location` + `temporal`) |
| Fórum / threading | Social + Annotation | `wom:Post` + `wom:Comment` + `relationships: [inReplyTo]` |
| Sala geolocalizada | Bindings | `bindings.irc` + `location` (geohash) |
| Briefing de sala | Core + Catalog | `wom:Entity` (lugar) + `wom:Signal` (stats) + pinned `wom:Note` |
| Estabelecimento (bot) | Commercial + Catalog | `wom:Merchant` + `wom:Offer` + `wom:BusinessEvent` |
| Pagamento (Lightning) | Commercial + Governance | `wom:BusinessEvent` + `wom:CommerceSignal` + `wom:ConversionEvent` |
| WircCard (identidade) | Identity | `wom:Profile` + `wom:RemoteIdentity` + `wom:Membership` |
| Motoclube (club badge) | Identity + Governance | `wom:Organization` + `wom:Membership` + `proof` (assinatura) |
| Modo Aberto (mesh) | Bindings + Transport | `bindings.bitchat` + `governance.sharing: public` |
| Modo Full Mesh (anônimo) | Transport | `bindings.bitchat` + `attributedTo: null` + `proof: null` |
| Email newsletter | Bindings + Publication | `bindings.email` + `publication.status` |
| Enriquecimento (Wikimedia) | Identification & Mapping | `wom:Mapping` + `wom:ExternalIdentifier` + `wom:Descriptor` |
| Discovery transitivo | Attention + Social | `wom:TrustRelation` + `wom:Collection` (shared subscriptions) |
| Proximity Tap | Identity + Social | `wom:Contact` + `wom:Signal` (signalType: "met_in_person") |
| Segurança de menores | Governance | `governance.sharing: restricted` + `governance.requiresHumanApproval` |

---

## 2. Exemplos WOM 0.6 por Feature

### Bookmark (signal sobre conteúdo)
```json
{
  "wom": "0.6",
  "id": "urn:wom:signal:bkmk-001",
  "type": ["wom:Signal"],
  "createdAt": "2026-06-18T11:00:00-07:00",
  "attributedTo": {"id": "did:key:wilson", "type": ["Person", "wom:Profile"]},
  "data": {"signalType": "bookmarked"},
  "relationships": [
    {"type": "wom:object", "object": "urn:wom:object:article-advrider-001"}
  ],
  "governance": {"sharing": "friends_only", "retention": "indefinite"},
  "provenance": {"origin": "user_provided"}
}
```

### Classificado local (offer geolocalizado)
```json
{
  "wom": "0.6",
  "id": "urn:wom:offer:capacete-001",
  "type": ["wom:Offer", "wom:Product"],
  "createdAt": "2026-06-18T13:00:00-07:00",
  "name": "Capacete Shoei GT-Air II — tamanho M",
  "content": {"format": "text/plain", "text": "Pouco uso, sem quedas. Retirar em Victoria."},
  "attributedTo": {"id": "did:key:pedro", "type": ["Person"]},
  "commercial": {
    "intentStage": "available",
    "category": "motorcycle_gear",
    "value": 45000,
    "currency": "SAT"
  },
  "classification": {
    "semanticType": "commerce.product",
    "topics": ["marketplace", "gear", "helmets"],
    "category": {"scheme": "schema.org", "value": "Product"}
  },
  "location": {
    "type": "point",
    "coordinates": [48.4284, -123.3656],
    "radius": 30000,
    "relevanceScale": "city",
    "name": "Victoria, BC"
  },
  "temporal": {"type": "durable", "expiresAt": "2026-07-18T13:00:00-07:00"},
  "governance": {"sharing": "public", "retention": "30d"},
  "availability": [{"status": "available", "updatedAt": "2026-06-18T13:00:00-07:00"}],
  "bindings": {
    "irc": {"server": "irc.motosvic.ca", "channel": "#marketplace-victoria"},
    "nostr": {"geohash": "c2b2q", "tags": ["marketplace", "gear"]}
  }
}
```

### Hazard (alerta com expiração)
```json
{
  "wom": "0.6",
  "id": "urn:wom:signal:hazard-001",
  "type": ["wom:Signal", "wom:Event"],
  "createdAt": "2026-06-18T14:30:00-07:00",
  "data": {"signalType": "hazard", "category": "oil_spill", "severity": "high"},
  "location": {
    "type": "point",
    "coordinates": [-23.5505, -46.6333],
    "radius": 50,
    "relevanceScale": "block"
  },
  "temporal": {"type": "instantaneous", "expiresAt": "2026-06-18T16:30:00-07:00"},
  "governance": {"sharing": "public", "retention": "2h"},
  "provenance": {"origin": "user_provided", "confidence": 1.0},
  "bindings": {
    "nostr": {"geohash": "6gyf4b", "tags": ["wawa-hazard"]},
    "bitchat": {"ttl": 255, "relay": "unlimited"}
  }
}
```

### Interação como broadcast (cascata social)
```json
{
  "wom": "0.6",
  "id": "urn:wom:signal:like-001",
  "type": ["wom:Signal", "wom:Reaction"],
  "createdAt": "2026-06-18T15:00:00-07:00",
  "attributedTo": {"id": "did:key:wilson"},
  "data": {"signalType": "liked"},
  "relationships": [
    {"type": "wom:object", "object": "urn:wom:offer:capacete-001"}
  ],
  "governance": {"sharing": "public"},
  "provenance": {
    "origin": "user_provided",
    "path": ["did:key:pedro", "did:key:wilson"]
  }
}
```
Efeito: `urn:wom:offer:capacete-001` agora propaga para seguidores de Wilson (via provenance.path que cresce a cada hop).

### WircCard (identidade + membership)
```json
{
  "wom": "0.6",
  "id": "urn:wom:profile:joao-001",
  "type": ["wom:Profile", "Person"],
  "createdAt": "2026-01-15T10:00:00-07:00",
  "identity": {
    "canonicalId": "did:key:joao-pubkey",
    "canonicalStatus": "canonical"
  },
  "labels": [
    {"value": "João Motoca", "language": "pt-BR", "role": "preferred"},
    {"value": "joao_rider", "role": "alias"}
  ],
  "data": {
    "bike": "Tenere 700 2024",
    "city": "Victoria, BC",
    "avatar": "🦅"
  },
  "relationships": [
    {"type": "wom:memberOf", "object": "urn:wom:org:brazoocas-mc"}
  ],
  "proof": {
    "type": "Ed25519Signature",
    "signature": "base64...",
    "verificationMethod": "did:key:joao-pubkey"
  }
}
```

### ClubBadge (membership verificável)
```json
{
  "wom": "0.6",
  "id": "urn:wom:membership:joao-brazoocas",
  "type": ["wom:Membership", "wom:Credential"],
  "createdAt": "2026-03-01T10:00:00-07:00",
  "attributedTo": {"id": "urn:wom:org:brazoocas-mc", "type": ["Organization"]},
  "relationships": [
    {"type": "wom:member", "object": "did:key:joao-pubkey"},
    {"type": "wom:organization", "object": "urn:wom:org:brazoocas-mc"}
  ],
  "data": {"role": "member"},
  "proof": {
    "type": "Ed25519Signature",
    "signature": "base64...",
    "verificationMethod": "did:key:brazoocas-club-pubkey"
  }
}
```

### Evento com ecossistema (atrator gravitacional)
```json
{
  "wom": "0.6",
  "id": "urn:wom:event:passeio-serra-001",
  "type": ["wom:Event", "wom:Invite"],
  "name": "Passeio Serra do Rio — Sábado 7h",
  "createdAt": "2026-06-16T20:00:00-07:00",
  "attributedTo": {"id": "did:key:marcos"},
  "location": {
    "type": "point",
    "coordinates": [-22.9068, -43.1729],
    "radius": 500,
    "name": "Posto Shell Centro"
  },
  "temporal": {
    "type": "eventual",
    "startsAt": "2026-06-22T07:00:00-03:00",
    "endsAt": "2026-06-22T14:00:00-03:00"
  },
  "governance": {"sharing": "public"},
  "bindings": {
    "irc": {"channel": "#passeio-serra"},
    "nostr": {"geohash": "75cm", "tags": ["wawa-beacon", "motorcycle"]}
  }
}
```
RSVPs, classificados ("divide gasolina"), hazards na rota e info (previsão do tempo) se agrupam via `relationships: [{ type: "wom:relatedTo", object: "urn:wom:event:passeio-serra-001" }]`.

### Pagamento (transaction como WOM)
```json
{
  "wom": "0.6",
  "id": "urn:wom:event:payment-001",
  "type": ["wom:BusinessEvent", "wom:CommerceSignal", "wom:ConversionEvent"],
  "createdAt": "2026-06-18T15:30:00-07:00",
  "attributedTo": {"id": "did:key:wilson"},
  "commercial": {
    "intentStage": "purchase",
    "value": 500,
    "currency": "SAT",
    "attribution": {
      "source": "recommendation",
      "recommendedBy": "did:key:joao",
      "object": "urn:wom:collection:joao-motos"
    }
  },
  "relationships": [
    {"type": "wom:object", "object": "urn:wom:collection:joao-motos"},
    {"type": "wom:recipient", "subject": "did:key:wilson", "object": "did:key:joao"}
  ],
  "measurement": {
    "eventName": "zap_sent",
    "observationType": "observed",
    "confidence": 1.0
  },
  "governance": {"sharing": "local_only", "adsUse": "not_allowed"}
}
```

### Modo Full Mesh (anônimo)
```json
{
  "wom": "0.6",
  "id": "urn:wom:signal:anon-hazard-001",
  "type": ["wom:Signal"],
  "createdAt": "2026-06-18T16:00:00-07:00",
  "attributedTo": null,
  "data": {"signalType": "hazard", "category": "police_advance", "text": "Avançando pela Rua X"},
  "location": {"type": "point", "coordinates": [-23.55, -46.63], "radius": 100},
  "temporal": {"type": "instantaneous", "expiresAt": "2026-06-18T17:00:00-07:00"},
  "governance": {"sharing": "public", "retention": "1h"},
  "provenance": null,
  "proof": null,
  "bindings": {
    "bitchat": {"ttl": 255, "anonymous": true, "peerIdRotation": "60s"}
  }
}
```
Sem `attributedTo`, sem `proof`, sem `provenance`. Irrastreável.

---

## 3. Campos WOM 0.6 que o Wirc usa extensivamente

| Campo WOM | Uso no Wirc |
|-----------|-------------|
| `governance.sharing` | Controla propagação: local_only / friends_only / public |
| `governance.retention` | Tempo de vida do WOM na rede (30d, 2h, indefinite) |
| `provenance.origin` | De onde veio: user_provided, remote_peer, assistant_generated |
| `provenance.path` | Cadeia de propagação ("via João → Carlos → YouTube") |
| `location` | Descoberta por proximidade, salas geo, hazards, classificados |
| `temporal` | Expiração, eventos futuros, recorrência |
| `relationships` | Threading (inReplyTo), cascata (object), membership (memberOf) |
| `bindings.irc` | Canal IRC onde o WOM existe/foi publicado |
| `bindings.nostr` | Relay + geohash + tags para discovery |
| `bindings.bitchat` | Mesh BLE config (TTL, anonymous, relay mode) |
| `proof` | Assinatura Ed25519 para identidade/integridade verificável |
| `commercial` | Marketplace, pagamentos, atribuição |
| `classification.topics` | Filtragem temática (feed por topic) |
| `availability` | Status de ofertas (available, sold, closed) |
| `data` | Key-value flexível para campos específicos do Wirc (signalType, bike, avatar) |

---

## 4. Perfis WOM 0.6 utilizados pelo Wirc

| Perfil WOM 0.6 | Uso no Wirc |
|----------------|-------------|
| **Social Profile** | Feed, posts, reações, follows, collections, recommendations |
| **Commercial Profile** | Marketplace, classificados, pagamentos, atribuição |
| **Transport Profile** | Bindings IRC/Nostr/BitChat, envelopes, roteamento |
| **Catalog Profile** | Listas curadas, subscriptions como coleções |
| **Personal Profile** | Bookmarks, notas pessoais, histórico local |
| **Identification & Mapping** | WircCards, ClubBadges, mappings Wikidata, entidades |
| **Annotation Profile** | Promoção de chat → hazard/review (annotation com target) |

Perfis NÃO usados no MVP: Journalism, Source Protection, Archive, Knowledge, Editorial, Knowledge Organization.

---

## 5. Campos WOM 0.6 que o Wirc NÃO usa (MVP)

| Campo/Camada | Motivo de exclusão |
|-------------|-------------------|
| `journalism`, `editorial`, `slug`, `byline` | Wirc não é CMS jornalístico |
| `sourceProtection` | Sem fontes protegidas no uso social |
| `archive`, `preservationSnapshot` | Sem preservação formal no MVP |
| `statements`, `claims`, `evidence` | Sem camada de knowledge verification |
| `measurement.modelled` | Sem dados modelados |
| `commercial.campaign` | Sem campanhas publicitárias |
| `rights.aiTrainingUse` | Irrelevante para chat/feed social |

Esses campos existem no WOMObject mas ficam `null`/omitidos. Parser ignora campos desconhecidos (regra 1 do WOM 0.6).

---

## 6. Como o WOM 0.6 resolve decisões de design do Wirc

| Decisão Wirc | Mecanismo WOM 0.6 |
|-------------|-------------------|
| "Quem vê o quê" | `governance.sharing` (local_only → public) |
| "Quanto tempo vive" | `governance.retention` + `temporal.expiresAt` |
| "De onde veio" | `provenance` (origin, actor, source, path, confidence) |
| "É real?" | `proof` (Ed25519 signature, verificationMethod) |
| "É do clube?" | `wom:Membership` + `proof` assinado pela org |
| "Pode propagar?" | `governance.sharing != local_only` + `governance.retention > 0` |
| "Para onde vai?" | `bindings` (irc, nostr, bitchat, email) — multi-canal |
| "Quão relevante?" | `location` × `temporal` × trust graph (atenção) |
| "É anônimo?" | `attributedTo: null` + `proof: null` + `bindings.bitchat.anonymous: true` |
| "Posso pagar?" | `commercial` (value, currency, attribution) via NWC |
| "Expirou?" | `temporal.expiresAt` < now → descarta |
| "É resposta?" | `relationships: [{ type: "inReplyTo" }]` |
| "Posso enriquecer?" | `mappings` + `wom:ExternalIdentifier` (Wikidata Q-IDs) |

---

## 7. Compatibilidade com padrões (via WOM 0.6)

O Wirc herda do WOM 0.6 a compatibilidade com:

| Padrão | O que o Wirc ganha |
|--------|-------------------|
| Schema.org | Types comuns (Person, Product, Event, CreativeWork) nos WOMs |
| ActivityStreams | Posts, reactions, follows mapeáveis para/de ActivityPub (Mastodon) |
| W3C DID | Identidade (`did:key:...`) verificável sem servidor central |
| ODRL | `governance` como políticas de uso formais |
| JSON-LD | Exportação semântica interoperável (futuro) |
| SKOS | Vocabulários controlados em `classification` e `descriptors` |
| W3C PROV-O | `provenance` mapeia para modelo PROV padrão |

---

## 8. WOM Bundle como export do Wirc

O usuário pode exportar seus dados (portabilidade):

```
wirc-export-wilson-2026-06/
  manifest.json          → metadata do bundle
  objects/               → posts, bookmarks, notas
  signals/               → likes, reactions, follows
  events/                → hazards, ride beacons, meetups
  entities/              → WircCards de contatos
  catalog/               → listas curadas, subscriptions
  mappings/              → Wikidata IDs, bindings
```

Reimportável em qualquer outro Wirc (ou app que entenda WOM 0.6). **O app não é a prisão do dado.**

---

## 9. WOM Lite (Transmissão Compacta)

### Problema
WOM completo pode ter 30+ campos, 500-2000 bytes. Transmitir pela mesh/IRC/Nostr é wasteful. O receptor precisa renderizar um card, não processar o objeto inteiro.

### Solução: WOM Lite + hash do completo

```json
{
  "wom": "0.6",
  "id": "urn:wom:offer:capacete-001",
  "type": ["wom:Offer"],
  "createdAt": "2026-06-18T13:00:00-07:00",
  "attributedTo": {"id": "did:key:pedro"},
  "content": {"text": "Capacete Shoei GT-Air II — $400"},
  "governance": {"sharing": "public"},
  "data": {"signalType": "offer", "category": "gear"},
  "_lite": {
    "fullHash": "sha256:a1b2c3d4e5f6...",
    "fullSize": 847,
    "version": 1,
    "previousHash": null,
    "fields": ["commercial", "location", "classification", "availability", "proof"]
  }
}
```

### WOM Lite (~150 bytes) vs WOM Completo (~800+ bytes)
| | WOM Lite | WOM Completo |
|--|---|---|
| Onde vive | Transmitido (IRC, Nostr, mesh) | Storage local (GRDB) |
| Campos | 5-8 essenciais + `_lite` | 30+ campos |
| Suficiente para | Renderizar card no feed | Detalhes, verificação, mapa |
| Hash | Contém hash do completo | É o objeto hasheado |

### Quando pedir o completo?
| Situação | Ação |
|----------|------|
| Scroll no feed | Lite basta |
| Tap no card (abrir) | Pedir completo (detalhes, location, commercial) |
| Verificar assinatura | Precisa completo (proof) |
| Navegar até local | Precisa completo (location) |
| Offline | Só Lite; pede completo quando tiver conexão |

### Canonicalização (hash determinístico)
Para hash ser consistente independente de quem calcula:
- Campos ordenados alfabeticamente (recursivo)
- Sem espaços/indentação
- Unicode normalizado (NFC)
- Campo `_lite` excluído do hash (não inclui a si mesmo)

Mesmo padrão que Nostr usa para event IDs.

### `_lite.fields` — o que falta
Lista campos top-level que existem no completo mas não no Lite. Receptor sabe de antemão o que ganha ao pedir full.

---

## 10. Versionamento Encadeado por Hash

### Princípio
Cada versão de um WOM contém o hash da versão anterior. WOM Lite da versão mais recente carrega o hash atual (que contém o da anterior). Cadeia verificável como git commits.

### Cadeia
```
V1 (original):    hash: aaa111, previousHash: null
V2 (editou preço): hash: bbb222, previousHash: aaa111
V3 (vendido):      hash: ccc333, previousHash: bbb222

Cadeia: ccc333 → bbb222 → aaa111 → null
```

Mesmo `id` ao longo da cadeia. Hash muda a cada edição.

### No WOM Completo
```json
{
  "revision": {
    "version": 3,
    "hash": "sha256:ccc333...",
    "previousHash": "sha256:bbb222...",
    "updatedAt": "2026-06-18T16:00:00-07:00",
    "updatedBy": "did:key:pedro"
  }
}
```

### No WOM Lite
```json
{
  "_lite": {
    "fullHash": "sha256:ccc333...",
    "version": 3,
    "previousHash": "sha256:bbb222..."
  }
}
```

### O que habilita
| Capacidade | Como |
|------------|------|
| Verificar integridade | `sha256(full) == _lite.fullHash` |
| Detectar atualização | Mesmo id, version maior, previousHash aponta pro que eu já tinha |
| Reconstruir histórico | Seguir cadeia v3 → v2 → v1 |
| Detectar conflito (fork) | Duas versões com mesmo previousHash mas hashes diferentes |
| Prova de existência | "Este objeto existia em v1 naquela data" |

### Conflito (edições offline divergentes)
```
V1 (hash: aaa)
  ├── V2a (eu editei offline):   hash bbb, previous: aaa
  └── V2b (João editou offline): hash ccc, previous: aaa

Sincroniza → "duas versões com previous = aaa" → conflito detectado.
Resolução: timestamp (recente ganha) | trust (autor original decide) | merge | last-write-wins
```

### Resumo
5 campos (`version`, `hash`, `previousHash`, `updatedAt`, `updatedBy`). Cadeia completa. Verificável. Detecta conflito. Funciona offline. Lite carrega hash que encadeia tudo.

---

## 11. Assinaturas e Criptografia

### Princípio: assinar hashes, não conteúdo
Em vez de assinar JSON inteiro (grande, canonicalização cara), assinar o **hash de 32 bytes** — fixo, instantâneo. Versões assinam hash que contém assinatura anterior (cadeia).

### Modelo
```
hash = sha256(canonical_json)           ← O(N), feito 1x na criação
signature = sign(hash_32bytes, privkey) ← constante, ~0.1ms
verify(signature, hash, pubkey)         ← constante, ~0.2ms
```

### Cadeia de assinaturas (Merkle chain por objeto)
```
V1: hash1 = sha256(content_v1)
    sig1 = sign(hash1, privkey)

V2: hash2 = sha256(content_v2 + hash1 + sig1)  ← inclui hash E sig anterior
    sig2 = sign(hash2, privkey)

V3: hash3 = sha256(content_v3 + hash2 + sig2)
    sig3 = sign(hash3, privkey)
```

**Verificar só o último = verificar toda a cadeia.** sig3 garante V3 que contém sig2 que garante V2 que contém sig1 que garante V1.

### No WOM Completo
```json
{
  "revision": {
    "version": 3,
    "hash": "sha256:ccc333...",
    "previousHash": "sha256:bbb222...",
    "previousSig": "base64(sig2)"
  },
  "proof": {
    "type": "Ed25519",
    "target": "sha256:ccc333...",
    "signature": "base64(sign(ccc333, privkey))",
    "verificationMethod": "did:key:pedro"
  }
}
```

### No WOM Lite (verificável standalone)
```json
{
  "_lite": {
    "fullHash": "sha256:ccc333...",
    "version": 3,
    "proof": "base64(sign(ccc333, privkey))"
  }
}
```
3 campos. Receptor faz: `verify(proof, fullHash, pubkey)` → ✓ = autêntico E cadeia inteira válida.

### Custo
| Operação | Bytes | CPU |
|----------|-------|-----|
| Hash do conteúdo | N (1x) | O(N), só na criação |
| Assinar | 32 fixo | ~0.1ms |
| Verificar | 32 fixo | ~0.2ms |
| Verificar cadeia | 32 fixo (só último) | ~0.2ms (1 verify = tudo) |

### Criptografia (confidencialidade)
Para `governance.sharing: friends_only / group_only / direct_recipient`:

```json
{
  "content": null,
  "data": null,
  "_encrypted": {
    "algorithm": "XChaCha20-Poly1305",
    "keyAgreement": "X25519",
    "recipients": ["did:key:joao", "did:key:ana"],
    "nonce": "base64...",
    "ciphertext": "base64...(content + data cifrados)..."
  }
}
```

Em claro (para roteamento): `wom`, `id`, `type`, `createdAt`, `attributedTo`, `governance.sharing`, `_lite`.
Cifrado: `content`, `data`, `commercial`, `location` (campos sensíveis).

### Tabela por governance.sharing
| sharing | Assinado? | Encriptado? | Quem lê |
|---------|:---------:|:-----------:|---------|
| public | ✅ | ❌ | Qualquer um |
| friends_only | ✅ | ✅ (recipients = amigos) | Só amigos |
| group_only | ✅ | ✅ (recipients = membros) | Só grupo |
| direct_recipient | ✅ | ✅ (1 recipient) | Só destinatário |
| local_only | ✅ | N/A (nunca sai) | Só eu |

### Versionamento + criptografia
Novo membro = nova versão com recipient set expandido. Versões antigas mantêm recipients antigos (forward secrecy por versão: quem entrou não lê passado, quem saiu não lê futuro).

---

## 12. Modelo de Confiança: Endereços, não Identidades

### O problema a resolver
Queremos que um WOM garanta:
1. **Integridade** — conteúdo não foi alterado
2. **Autoria legítima** — alguém real criou isso (não é fabricado)
3. **Endosso de relay** — quem me entregou atesta que é legítimo

**SEM** revelar identidades para quem não precisa saber.

### O insight: identidade vive na RELAÇÃO, não no objeto

```
Uma pubkey é um número. Não é um nome.
Só vira identidade para quem já mapeou esse número a uma pessoa.
Se eu e João trocamos WircCards, eu CONHEÇO a pubkey dele.
Se um estranho vê a mesma pubkey: é só um número.
```

A identidade não está no WOM. Está no mapeamento local que cada pessoa mantém (WircCards no GRDB).

### Aplicando o modelo Bitcoin

Bitcoin nunca expõe pubkeys diretamente em transações. Expõe **endereços** — que são hashes de pubkeys. Compactos, pseudônimos, irrastreáveis sem a pubkey original.

O mesmo princípio aplicado ao WOM:

```
Em vez de:   pubkey (32 bytes, identificável por quem tem)
Usar:        address = hash(pubkey) (20 bytes, verificável por quem tem a pubkey)
```

### Construção passo a passo

**1. Autor cria o WOM:**
```
content_hash = sha256(wom_content)
author_sig = sign(content_hash, minha_privkey)
author_address = ripemd160(sha256(minha_pubkey))

WOM carrega:
  content_hash:   32 bytes  — impressão digital do conteúdo
  author_sig:     64 bytes  — prova de que o dono do address criou
  author_address: 20 bytes  — QUEM criou (sem revelar quem é)
```

**2. Relay (Carlos) retransmite:**
```
Carlos recebe o WOM. Quer endossar e repassar.

relay_sig = sign(author_sig, carlos_privkey)   — "endosso esta assinatura do autor"
relay_address = ripemd160(sha256(carlos_pubkey))

WOM agora carrega:
  content_hash:   32 bytes
  author_sig:     64 bytes
  author_address: 20 bytes
  relay_sig:      64 bytes  — endosso do último relay
  relay_address:  20 bytes  — QUEM endossou (sem revelar quem é)
```

**3. Próximo relay SUBSTITUI (não acumula):**
```
Lucia recebe de Carlos. Quer repassar.

relay_sig = sign(author_sig, lucia_privkey)   — Lucia endossa a assinatura do autor
relay_address = ripemd160(sha256(lucia_pubkey))

WOM agora carrega (SUBSTITUI relay anterior):
  content_hash:   32 bytes   (mesmo)
  author_sig:     64 bytes   (mesmo)
  author_address: 20 bytes   (mesmo)
  relay_sig:      64 bytes   (NOVO — Lucia)
  relay_address:  20 bytes   (NOVO — Lucia)
```

**Tamanho é SEMPRE 200 bytes. Fixo. Não cresce.**

### Verificação: quem pode, verifica. Quem não pode, confia.

```
Receptor recebe WOM:
  
  Passo 1 — Integridade:
    sha256(content) == content_hash? ✓ → conteúdo não foi alterado
    
  Passo 2 — Autoria:
    verify(author_sig, content_hash, ???)
    Preciso da pubkey cujo hash == author_address.
    
    Tenho WircCard do Pedro: hash(pedro_pubkey) == author_address? 
      Se ✓: verify(author_sig, content_hash, pedro_pubkey) ✓ → "Pedro criou"
      Se ✗: não sei quem criou, mas SEI que alguém com chave legítima criou
      
  Passo 3 — Endosso do relay:
    verify(relay_sig, author_sig, ???)
    Preciso da pubkey cujo hash == relay_address.
    
    Tenho WircCard do Carlos: hash(carlos_pubkey) == relay_address?
      Se ✓: verify(relay_sig, author_sig, carlos_pubkey) ✓ → "Carlos me entregou"
      Se ✗: não sei quem relay, mas SEI que alguém legítimo endossou
```

### O que cada ator vê

| Quem | Sabe que autor é Pedro? | Sabe que relay é Carlos? | Conteúdo íntegro? |
|------|:-:|:-:|:-:|
| Amigo de Pedro + Carlos | ✅ | ✅ | ✅ |
| Amigo só de Pedro | ✅ | ❌ (não reconhece relay) | ✅ |
| Amigo só de Carlos | ❌ (não reconhece autor) | ✅ | ✅ |
| Estranho (sem WircCards) | ❌ | ❌ | ✅ (hash bate, sabe que é íntegro) |
| Adversário | ❌ | ❌ | ✅ (mas não sabe de quem veio) |

### Por que addresses e não pubkeys

| | Pubkey no WOM | Address (hash) no WOM |
|--|---|---|
| Tamanho | 32 bytes | 20 bytes |
| Identificável por outsider | Sim (se cruzar com pubkey em outro lugar) | Não (hash é one-way) |
| Verificável por quem conhece | Sim | Sim (hash da pubkey que tenho → compara) |
| Correlacionável entre WOMs | Sim (mesma pubkey em vários WOMs = mesma pessoa) | Menos (address pode rotacionar se usar derivação) |

### Rotação de address (privacidade adicional)

Como Bitcoin gera novo endereço por transação, o Wirc pode derivar novo address por WOM:

```
relay_address_1 = hash(pubkey + salt_1) para WOM A
relay_address_2 = hash(pubkey + salt_2) para WOM B

Outsider não correlaciona: address_1 ≠ address_2 (parecem pessoas diferentes)
Quem tem minha pubkey + salt: reconhece ambos como meus
```

Salt pode ser: WOM ID, timestamp, ou counter. Receptor que me conhece tenta derivar com salts conhecidos.

### Resumo do modelo

```
WOM viaja com:
  content_hash (32B)   — integridade
  author_sig (64B)     — prova de autoria
  author_address (20B) — quem criou (pseudônimo)
  relay_sig (64B)      — endosso do relay
  relay_address (20B)  — quem retransmitiu (pseudônimo)
  = 200 bytes fixo

Verificação:
  Conteúdo íntegro? → qualquer um confirma (hash)
  Quem criou? → só quem tem a pubkey do autor confirma
  Quem relay? → só quem tem a pubkey do relay confirma
  Estranho? → sabe que é legítimo (sigs válidas) mas não sabe de quem

O WOM garante legitimidade sem identificar ninguém.
A identidade emerge da relação prévia (WircCard), não do objeto.
```

---

## 13. Full Mesh + Endereços Pseudônimos

### Mesmo formato, chaves efêmeras
O Modo Full Mesh usa o MESMO formato de 200 bytes. A diferença: chaves são efêmeras (nascem ao ativar, morrem ao desativar, rotam a cada 60s).

```
Modo Normal:   chave permanente → address estável → amigos reconhecem
Modo Full Mesh: chave efêmera (60s) → address rotativo → ninguém reconhece
```

O protocolo é indistinguível — receptor não sabe se WOM veio de modo normal ou Full Mesh (plausible deniability).

### O que garante
| Propriedade | Status |
|-------------|:------:|
| Conteúdo íntegro | ✅ |
| Alguém real assinou | ✅ (sig válida) |
| Identificável | ❌ (chave efêmera, address rotativo) |
| Dois WOMs correlacionáveis à mesma pessoa | ❌ (rota a cada 60s) |
| Phone apreendido revela autoria | ❌ (chaves apagadas ao desativar) |

### Confirmação crowd anônima
Dois WOMs com addresses diferentes + mesmo conteúdo semântico = 2 pessoas independentes reportaram. Mais confiável — sem saber quem é nenhuma das duas.

### Adversário com sniffer BLE
Captura WOMs do ar. Vê addresses todos diferentes (rotação). Não correlaciona. Não identifica. Sabe que há atividade mesh (inevitável — BLE é rádio) mas não sabe quem disse o quê.

### Forense no phone
Modo desativado = wipe. Chaves efêmeras apagadas. WOMs da sessão apagados. Addresses irrecuperáveis. Wirc em estado idle normal.

---

## 14. Encriptação: Camada de Acesso (Separada de Confiança)

### Princípio: são problemas ortogonais

| Camada | Pergunta | Mecanismo | Independente? |
|--------|----------|-----------|:---:|
| **Confiança** | "Quem criou? É legítimo?" | sig + address (envelope) | ✅ |
| **Acesso** | "Quem pode ler?" | encryption (payload) | ✅ |
| **Transporte** | "Como chega?" | IRC/Nostr/BLE (canal) | ✅ |

Três camadas. Nenhuma depende da outra. Combinam livremente.

### Todas as combinações são válidas

| Assinado | Encriptado | Uso |
|:---:|:---:|---|
| ✅ | ❌ | Post público, hazard, classificado |
| ✅ | ✅ | Mensagem privada para amigos/grupo |
| ❌ | ❌ | Full Mesh anônimo (manifestação) |
| ❌ | ✅ | Whistleblower anônimo para grupo fechado |

### Onde cada uma atua no WOM

```
Envelope (SEMPRE em claro, SEMPRE verificável):
  content_hash, author_sig, author_address, relay_sig, relay_address
  governance.sharing
  
Payload (controlado por governance.sharing):
  Se public:        content em cleartext
  Se friends/group: content como ciphertext
  Se local_only:    não transmitido
```

### Relay funciona sobre conteúdo encriptado SEM ler

Relay valida o envelope (sigs, hash) sem precisar decriptar o payload. Endossa e retransmite ciphertext opaco. O carteiro cego funciona igual para conteúdo encriptado — não precisa ler para garantir integridade e retransmitir.

### Encriptação é decisão do autor (governance)

```
governance.sharing: public       → cleartext
governance.sharing: friends_only → encriptado (recipients = amigos)
governance.sharing: group_only   → encriptado (recipients = membros)
governance.sharing: local_only   → nunca sai do device
```

Não é decisão do transporte. Não é do relay. É do WOM, declarada pelo autor no momento da criação.
