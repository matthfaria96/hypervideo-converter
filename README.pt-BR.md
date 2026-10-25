[English](README.md) · Português

# HyperVideo Converter

Um conversor de vídeo nativo para macOS no espírito do HandBrake, escrito do zero em Swift e SwiftUI. Ele codifica com os frameworks de mídia da própria Apple (AVFoundation e VideoToolbox), então H.264, HEVC e ProRes rodam nos codificadores de hardware do Mac. Também comprime vídeos para um tamanho-alvo e os amplia com IA (Real-ESRGAN, pelo Upscayl). Tudo roda no Mac; nada é enviado para a internet.

A interface está em inglês e português do Brasil (segue o idioma do Mac).

**Requisitos:** macOS 15 Sequoia ou mais novo, em Apple Silicon ou Intel (app universal). O visual Liquid Glass precisa do macOS 26 ou mais novo.

## Instalação

1. **Terminal, uma linha (recomendado).**

   ```bash
   curl -fsSL https://witchmymac.com/install.sh | bash -s hypervideo
   ```

   Ele baixa a versão mais recente do GitHub, confere o SHA-256, instala o app em Aplicativos e o abre. Não aparece aviso do Gatekeeper, porque arquivos baixados pelo `curl` não ficam em quarentena. Rodar de novo atualiza o app.

2. **Baixe o DMG** em [Releases](https://github.com/matthfaria96/hypervideo-converter/releases) ou em [witchmymac.com](https://witchmymac.com), abra e arraste o **HyperVideo Converter** para Aplicativos. O app não é notarizado pela Apple, então libere-o uma vez no Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/HyperVideo Converter.app"
   ```

   Isso só tira do app a marca de "baixado da internet".

3. **Baixe o DMG** e libere-o pelos Ajustes do Sistema: abra o app, clique em **OK** no aviso, depois vá em **Ajustes do Sistema → Privacidade e Segurança** e clique em **Abrir Mesmo Assim**.

## Três modos

A barra de ferramentas alterna entre três modos (⌘1, ⌘2, ⌘3). A lista de vídeos fica à esquerda, o painel de ajustes à direita, e a barra de conversão fica presa ao pé do painel: pasta de destino, uma linha de status (progresso, o que está pronto e o tamanho antes → depois) e os botões Prévia, Converter e Parar.

- **Converter.** As oito abas do HandBrake dentro do painel: Resumo, Dimensões, Filtros, Vídeo, Áudio, Legendas, Capítulos e Tags. Elas editam o vídeo selecionado ou todos de uma vez (corte, recorte, listas de faixas, nomes de capítulos e o título continuam sendo de cada vídeo). O seletor de Predefinição no topo reúne os perfis de qualidade, as predefinições prontas e as suas.
- **Comprimir.** Só as escolhas do dia a dia. **Por qualidade** usa um perfil de qualidade; **Por tamanho** mantém cada vídeo abaixo de um alvo ("no máximo 25 MB por vídeo", com atalhos para Discord, WhatsApp e e-mail): a taxa de bits do HEVC preenche o alvo depois do áudio, e a resolução diminui quando a imagem ficaria com bits de menos.
- **AI Upscale.** Amplia vídeos em 2×, 3× ou 4× com modelos Real-ESRGAN na GPU do Mac, com limite opcional de 4K. A Prévia do resultado mostra a nova resolução, o tamanho do arquivo (com o aumento em porcentagem) e o tempo estimado antes de começar. O Peso do arquivo (Leve, Equilibrado, Alta qualidade) e o codec evitam que o resultado fique pesado demais. O áudio é copiado sem alteração.

A **Prévia** gera um trecho real de dois segundos (alguns quadros no AI Upscale) com um divisor antes/depois que dá para arrastar e o tamanho projetado a partir do trecho, antes de converter o lote inteiro.

Embaixo da lista, o rodapé abre o **Histórico** (conversões concluídas, com falha e canceladas, com Mostrar no Finder, Abrir, Tentar de novo e Remover) e as **Predefinições** (aplicar, usar como padrão, salvar, renomear, apagar, importar do HyperVideo ou do HandBrake, exportar). Clique com o botão direito num vídeo para **Analisar** (fluxos, faixas, capítulos e detalhes do arquivo), Adicionar à fila, Mostrar no Finder e Remover.

## Recursos

- **Vídeo:** H.264, HEVC, HEVC 10 bits (mantém em HDR as origens HDR10 e HLG), Apple ProRes 422 / 422 HQ / 4444, ou passthrough sem recodificar.
- **Saída:** MP4, M4V, MOV, MKV ou só áudio (M4A).
- **Qualidade:** qualidade constante ou taxa de bits média, prioridade de velocidade, quadros B e intervalo de quadros-chave.
- **Imagem:** recorte (manual ou detectando as faixas pretas), girar, espelhar, reduzir até uma resolução máxima (vídeo vertical continua vertical), bordas e conversão da taxa de quadros.
- **Filtros:** desentrelaçamento (automático para origens marcadas como entrelaçadas), redução de ruído, suavização de croma, nitidez, espaço de cores e tons de cinza, na GPU pelo Core Image.
- **Áudio:** AAC com mixagem mono, estéreo ou 5.1, HE-AAC, Apple Lossless, passthrough ou sem áudio; primeira faixa, todas ou uma lista de faixas escolhidas, uma versão extra, ganho e nomes de faixa.
- **Legendas:** legendas de texto e closed captions são copiadas com o idioma. Arquivos SRT e WebVTT entram sozinhos quando estão ao lado do vídeo com o mesmo nome (`Filme.srt`, `Filme.pt-BR.srt`), ou por Adicionar arquivo de legenda…. Uma legenda de texto por vídeo pode ser gravada na imagem.
- **Capítulos e tags:** marcadores de capítulo (cortados junto com o vídeo), nomes de capítulos editáveis com importação/exportação em CSV, e tags descritivas (título, atores, diretor, data de lançamento, gênero, descrição, sinopse).
- **Corte:** um player embutido para marcar início e fim.
- **Predefinições:** quatro perfis de qualidade (Equilibrado, Alta qualidade, Arquivo menor, Manter original) e predefinições prontas para uso geral, 4K e HDR, aparelhos Apple, web, produção em ProRes e remux. Dá para importar predefinições exportadas do HandBrake; o que o HyperVideo não reproduz vira a opção mais próxima e aparece listado.
- **Fila:** várias conversões ao mesmo tempo, sobrevive a reabrir o app, mostra velocidade e tempo restante, progresso no Dock e uma notificação quando a fila termina. Sair durante uma conversão cancela tudo de forma limpa e devolve os vídeos à fila para a próxima vez.
- **Adicionar arquivos:** solte arquivos ou pastas inteiras em qualquer lugar da janela, use Escolher vídeos…, o Abrir Com do Finder ou o ícone no Dock. Arquivos ilegíveis aparecem marcados na lista com uma mensagem clara.

## Comparado com o HandBrake

O HyperVideo Converter é uma implementação nova, não um port do código do HandBrake. Ele troca a abrangência do HandBrake por um app nativo com codificação por hardware em tudo.

| | HyperVideo Converter | HandBrake |
|---|---|---|
| Motor | AVFoundation + VideoToolbox | FFmpeg / libav, x264, x265 |
| Formatos de entrada | O que o macOS lê (MOV, MP4, M4V, muitos formatos de câmera) | Quase tudo, incluindo MKV, WebM, AVI e DVD/Blu-ray |
| Contêineres de saída | MP4, M4V, MOV, MKV, M4A | MP4, MKV, WebM |
| Codecs | H.264, HEVC (8/10 bits), ProRes, passthrough | Também AV1, VP9, MPEG-2, Theora e x264/x265 em software |
| Ampliação com IA | Real-ESRGAN (Upscayl) | Não |

Limites que vêm de usar os frameworks do macOS: sem entrada MKV, WebM ou AV1 a menos que o próprio macOS decodifique o arquivo; sem ripar DVD ou Blu-ray; sem saída WebM; ProRes e closed captions precisam de MOV. A saída MKV é feita por um pequeno muxer Matroska embutido (Swift puro, sem FFmpeg) que copia as amostras codificadas para o `.mkv` sem recodificar; o QuickTime Player não abre MKV, então use VLC, IINA ou outro player de Matroska.

## Compilação

Requisitos: Xcode 26 ou mais novo (Swift 6.2). Só com as Command Line Tools, aponte o `DEVELOPER_DIR` para o Xcode.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
Scripts/build-app.sh            # versão release: dist/HyperVideo Converter.app e um DMG
Scripts/build-app.sh debug      # versão debug
swift test                      # testes unitários e de integração
```

O script gera um app universal (`ARCHS="arm64"` gera uma arquitetura só), regrava o SDK real com o `vtool` (o SwiftPM grava o alvo mínimo como SDK, o que desligaria o Liquid Glass), copia as traduções e a cor de destaque para o pacote, desenha o ícone com `Scripts/make-icon.swift`, baixa o motor e os modelos do Upscayl quando faltam (`Scripts/fetch-upscayl.sh`, versões fixas conferidas com SHA-256) e assina ad hoc. A versão vem da última tag do git (`v1.0.0` → `1.0.0`) e o número de build da contagem de commits. `SIGN_IDENTITY` e `NOTARY_PROFILE` assinam com um Developer ID e notarizam.

## Estrutura

```
Sources/HyperVideoCore        Motor de conversão e modelos (sem UI): pipeline, muxer Matroska, AI Upscale
Sources/HyperVideoConverter   App SwiftUI: estado, painel, abas, lista, folhas; textos em pt-BR
Tests/                        Testes unitários e de integração (codificação real em clipes sintéticos)
Scripts/                      Scripts do pacote do app, do ícone e do download do Upscayl
```

## Licença e créditos

O HyperVideo Converter é software livre sob a [GNU General Public License v3.0](LICENSE). Copyright (C) 2026 Matheus Faria.

Componentes de terceiros que vão no app (textos em `Contents/Resources/Licenses/` e em Ajustes → Sobre → Licenças de código aberto):

- **Sparkle** ([sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle)): MIT. Atualizações dentro do app (HyperVideo Converter → Verificar Atualizações…).
- **Motor do Upscayl** (`upscayl-bin`, do [upscayl-ncnn](https://github.com/upscayl/upscayl-ncnn)): GNU AGPL v3.0. Roda como um programa separado que o app inicia; o código-fonte está no link acima. Ele se baseia no [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) (Copyright (c) 2021, Xintao Wang, BSD 3-Clause) e no ncnn da Tencent (BSD 3-Clause).
- **Modelos de IA:** Upscayl Standard, Upscayl Lite e Digital Art, do projeto [Upscayl](https://github.com/upscayl/upscayl) (AGPL v3.0); o High Fidelity é o [4xHFA2k](https://openmodeldb.info/models/4x-HFA2k), de Helaman (Philip Hofmann), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Modelos cuja licença proíbe uso comercial (Remacri, UltraSharp, Ultramix) não entram.

O app não contém código do FFmpeg. Vídeos de demonstração nas capturas do site: *Big Buck Bunny*, *Sintel* e *Tears of Steel* © Blender Foundation, CC BY.
