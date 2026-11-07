---
name: Dayli iOS Design System
colors:
  surface: '#fcf9f4'
  surface-dim: '#dcdad5'
  surface-bright: '#fcf9f4'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3ee'
  surface-container: '#f0ede9'
  surface-container-high: '#ebe8e3'
  surface-container-highest: '#e5e2dd'
  on-surface: '#1c1c19'
  on-surface-variant: '#48464b'
  inverse-surface: '#31302d'
  inverse-on-surface: '#f3f0eb'
  outline: '#79767c'
  outline-variant: '#cac5cb'
  surface-tint: '#615c68'
  primary: '#201c26'
  on-primary: '#ffffff'
  primary-container: '#35313c'
  on-primary-container: '#9f99a6'
  inverse-primary: '#cbc4d2'
  secondary: '#69577d'
  on-secondary: '#ffffff'
  secondary-container: '#e8d1ff'
  on-secondary-container: '#69577e'
  tertiary: '#102216'
  on-tertiary: '#ffffff'
  tertiary-container: '#25372a'
  on-tertiary-container: '#8ca08f'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e7e0ee'
  primary-fixed-dim: '#cbc4d2'
  on-primary-fixed: '#1d1a24'
  on-primary-fixed-variant: '#494550'
  secondary-fixed: '#eedbff'
  secondary-fixed-dim: '#d4beea'
  on-secondary-fixed: '#231436'
  on-secondary-fixed-variant: '#503f64'
  tertiary-fixed: '#d2e8d5'
  tertiary-fixed-dim: '#b7ccb9'
  on-tertiary-fixed: '#0d1f13'
  on-tertiary-fixed-variant: '#384b3d'
  background: '#fcf9f4'
  on-background: '#1c1c19'
  surface-variant: '#e5e2dd'
typography:
  display:
    fontFamily: Inter
    fontSize: 34px
    fontWeight: '700'
    lineHeight: 41px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 34px
    letterSpacing: -0.015em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 30px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 25px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '600'
    lineHeight: 22px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.005em
  body-md:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 21px
    letterSpacing: 0em
  body-sm:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
    letterSpacing: 0em
  label-md:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 13px
    letterSpacing: 0.02em
  caption:
    fontFamily: Inter
    fontSize: 10px
    fontWeight: '500'
    lineHeight: 12px
    letterSpacing: 0.03em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1.25rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

O design system traduz a filosofia "Sua vida, no seu ritmo" em uma experiência digital serena, deliberada e acolhedora para iOS. Alinhado de forma estrita às Apple Human Interface Guidelines (HIG), ele rejeita estímulos visuais agressivos, gamificação infantilizada e alertas de urgência artificiais. Em vez disso, adota um minimalismo sensorial que une a precisão arquitetônica nativa da Apple a uma atmosfera calorosa e tátil.

### Personalidade da Marca
- **Acolhedora e Consciente:** Reduz a carga cognitiva através de generoso respiro visual, tons orgânicos e microinterações táteis calmas.
- **Elegante e Estruturada:** Sofisticada, focada em jovens adultos e profissionais que buscam gerenciar carreira, saúde e vida pessoal em um único refúgio visual equilibrado.
- **Nativa e Invisível:** Respeita o comportamento orgânico do ecossistema iOS (transições elásticas, gestos de swipe, folhas modais `sheet`, feedback háptico sutil e barras de navegação translúcidas).

### Linguagem Visual
A abordagem funde o **Minimalismo Orgânico** ao acabamento nativo do iOS. As telas utilizam fundos térmicos em creme, eliminando o contraste estridente do branco padrão do sistema, enquanto os cards em branco puro flutuam com sombras quase imperceptíveis e contornos de 0.5pt. As cores de categoria atuam como acentos calmos, nunca como blocos maciços de saturação.

## Colors

A hierarquia cromática é construída sobre bases neutras quentes para proporcionar conforto óptico contínuo ao longo do dia, utilizando a paleta cromática semântica para diferenciar as esferas da rotina.

### Cores Base & Neutras
- **Background Primário Canvas (`#F8F5F0`):** O tom creme suave que acolhe a interface e reduz o cansaço visual.
- **Superfície / Cards (`#FFFFFF`):** Branco puro utilizado para criar contraste limpo sobre o fundo creme.
- **Borda Sutil de Superfície (`#EFECE6`):** Linha de contenção hairline (0.5pt a 1pt) para demarcação elegante sem peso visual.
- **Texto Principal (`#35313C`):** Grafite profundo que assegura contraste AAA sem a dureza do preto puro (#000000).
- **Texto Secundário (`#7D7886`):** Grafite intermediário para metadados, legendas e descrições subordinadas.
- **Divisor & Separadores (`#E8E4DC`):** Linhas ultrafinas de divisão interna de listas nativas.

### Cores de Domínio & Áreas de Vida (Acentos)
- **Lavanda (`#B8A3CE`):** Dedicado a Estudos, Foco Intelectual e Leitura.
- **Rosa Queimado (`#D69EAA`):** Vida Pessoal, Celebrações e Conquistas Afetivas.
- **Verde Sálvia (`#A3B8A6`):** Saúde, Academia, Hábitos Físicos e Bem-estar.
- **Azul Suave (`#9BB8CD`):** Compromissos Corporativos e Finanças (Trabalho no Banco).
- **Pêssego / Rosa Claro (`#F2C4B7`):** Autocuidado, Momentos de Pausa e Lazer.

### Regras de Aplicação
1. Nenhuma cor de destaque deve ser utilizada em preenchimentos totais de tela. Elas pertencem exclusivamente a tags, indicadores de status, barras de progresso, ícones de contexto e badges de categorização.
2. Estados desabilitados usam opacidade reduzida (35%) sobre `#7D7886`.
3. Para fundos de badges ou pílulas de categoria, combine o tom correspondente com 12% a 18% de opacidade sobre o fundo branco.

## Typography

A tipografia reflete a clareza e solidez exigidas pelo ambiente iOS. O design system prioriza pesos medianos e regulares estruturados em uma escala de leitura fluida, eliminando pesos ultraleves ou excessivamente pesados que degradam a legibilidade.

### Princípios de Tipografia
- **Títulos com Personalidade Calma:** `display` e `headline-lg` estabelecem os momentos de abertura com tracking levemente negativo, criando harmonia com os títulos grandes nativos do iOS (Large Titles).
- **Corpo com Ritmo Aberto:** A altura de linha relaxada (`line-height` proporcional a 1.4x–1.45x) preserva a clareza em notas, descrições de rotinas e listas longas.
- **Labels e Metadados:** Tipos em caixa alta devem ser restritos a cabeçalhos de seção compactos (`caption`), com leve aumento de `letter-spacing`.

## Layout & Spacing

A malha espacial adota a métrica clássica de 8pt (subdividida em 4pt para alinhamentos finos), assegurando total correspondência com a geometria de renderização das telas Retina.

### Estrutura de Grid e Margens
- **Margem de Tela do iOS (`margin`):** `1.25rem` (20pt) nas laterais do canvas, criando um frame arejado para o conteúdo.
- **Gutter Interno (`gutter`):** `1rem` (16pt) de distância horizontal entre cards em visualizações divididas (duas colunas no iPad ou widgets horizontais).
- **Safe Areas:** O topo respeita a área dinâmica da Dynamic Island/Notch com afastamento mínimo de 12pt abaixo da barra de status. A base reserva 34pt para o Home Indicator além da altura padrão de 49pt a 52pt da TabBar nativa.

### Densidade e Ritmo
- **Compacto (`space-xs`, `space-sm`):** Distâncias de 4pt e 8pt para ícones alinhados a rótulos, espaçamentos entre badges ou checkboxes e seus textos.
- **Padrão (`space-md`):** Padding interno de cards (16pt) e gaps entre itens em listas agrupadas.
- **Respiro Ampliado (`space-lg`, `space-xl`):** Espaçamentos verticais de 24pt e 32pt separando blocos temáticos distintos (ex.: bloco de Agenda vs. bloco de Hábitos do Dia).

## Elevation & Depth

A ilusão de profundidade evita sombras escuras ou projeções duras. O sistema baseia-se em camadas tonais e materiais foscos característicos do ecossistema Apple.

### Estratégia de Camadas
1. **Nível 0 (Lona Base):** Fundo contínuo em `#F8F5F0`.
2. **Nível 1 (Superfície Primária / Cards):** Placas em `#FFFFFF` assentadas sobre a base, com borda tátil de `0.5pt solid #EFECE6` e sombra ultra-difusa: `0px 4px 20px rgba(53, 49, 60, 0.03)`.
3. **Nível 2 (Cards em Destaque / Modais Flutuantes):** Elevação aumentada para elementos interativos em foco ou menus contextuais: `0px 8px 30px rgba(53, 49, 60, 0.06)`.
4. **Camada Translúcida (Barra Superior & TabBar):** Superfícies com preenchimento em 85% de opacidade sobre a cor base combinadas com filtro nativo de desfoque de fundo (`backdrop-filter: blur(20px)`), permitindo que o conteúdo passe suavemente por trás dos controles de navegação.

## Shapes

A linguagem de formas segue as curvas contínuas (squircle / continuous corners) características do hardware e software da Apple, evitando cantos vivos.

### Regras de Geometria
- **Containers e Cards Principais:** Devem adotar raio contínuo de `20px` a `24px` (`rounded-xl` / `1.5rem`), conferindo toque amigável e suave sem perder o porte arquitetônico.
- **Campos de Entrada e Seletores:** Raio de `12px` a `14px` (`rounded-lg` / `1rem`), equilibrando estabilidade e conforto visual.
- **Badges, Tags e Chips:** Construção estritamente em pílula completa (`border-radius: 9999px`), assegurando que atuem como marcadores identificáveis.
- **Folhas Modais (`Sheets`):** Cantos superiores arredondados com `28px` contínuos, com a barra indicadora de arraste (drag handle) em `#7D7886` com 25% de opacidade.

## Components

Instruções para implementação dos principais componentes visuais do aplicativo:

### 1. Barra de Navegação Inferior (TabBar Nativa)
- **Estrutura:** 5 abas semânticas:
  1. **Hoje:** Ícone de sol calmo / dia corrente.
  2. **Agenda:** Ícone de calendário limpo em grade.
  3. **Tarefas:** Ícone de checklist em formato pílula.
  4. **Minha Vida:** Ícone de esfera equilibrada / folhas representando os pilares.
  5. **Perfil:** Ícone de monograma / silhueta refinada.
- **Comportamento:** Fundo translúcido com `backdrop-filter: blur(25px)`, preenchimento `#F8F5F0` a 82%. Ícone e texto selecionado em `#35313C`. Ícones e textos inativos em `#7D7886`. Tipografia do rótulo em `label-sm`.

### 2. Cards de Atividade e Blocos Diários
- **Construção:** Fundo `#FFFFFF`, raio de curvatura de 22px, borda perimetral de 0.5pt em `#EFECE6`.
- **Organização Interna:** Margem interna de 16pt a 20pt. Cabeçalho com pílula de categoria à esquerda e horário/status em `caption` à direita. 
- **Marcação Lateral:** Quando o card tiver vínculo forte com uma categoria (ex.: "Reunião de Crédito" para Trabalho no Banco), pode exibir um filete vertical esquerdo de 4px na cor `#9BB8CD` ou uma pílula de acento no topo.

### 3. Botões de Ação
- **Botão Primário:** Fundo em `#35313C`, texto em `#FFFFFF`, altura de 50pt, raio de 16px, peso `headline-sm`. O clique ativa feedback háptico leve (`UIImpactFeedbackGenerator(style: .light)`).
- **Botão Secundário:** Fundo em `#FFFFFF`, borda de 1pt em `#EFECE6`, texto em `#35313C`, raio de 16px.
- **Botão Fantasma / Inline:** Apenas texto em `#7D7886` ou na cor de acento de contexto, sem borda nem fundo.

### 4. Chips e Pílulas de Categoria
- **Dimensões:** Altura fixa de 28pt a 32pt, preenchimento horizontal de 12pt, raio 9999px.
- **Estilo Padrão:** Fundo na cor de acento com 14% de opacidade, texto e ícone no tom do acento correspondente em alto contraste (ex.: Estudos utiliza fundo `rgba(184, 163, 206, 0.18)` e tipografia em `#6B5283`).

### 5. Checkboxes de Hábitos e Tarefas
- **Geometria:** Círculos perfeitos de 24pt de diâmetro (evitar caixas quadradas para afastar a sensação de burocracia).
- **Estado Inativo:** Borda circular de 1.5pt em `#E8E4DC`, fundo transparente.
- **Estado Concluído:** Fundo preenchido com a cor da categoria (ex.: `#A3B8A6` para Saúde) com ícone de checkmark fino em `#FFFFFF`. Transição elástica de escala suave (spring animation) acompanhada de vibração háptica suave.

### 6. Campos de Texto e Inputs
- **Estrutura:** Fundo `#FFFFFF`, borda perimetral de 1pt em `#EFECE6`, cantos com raio de 14px, altura de 48pt, texto em `body-lg`.
- **Estado Ativo (Foco):** A borda muda suavemente para `#35313C` com transição de 200ms. Placeholder sempre em `#7D7886` com 60% de opacidade.

### 7. Listas Agrupadas (Grouped Inset Lists)
- As listas de configurações e subitens seguem rigorosamente o padrão iOS Inset Grouped: blocos brancos flutuantes sobre o fundo `#F8F5F0`, cantos de 20px, com separadores internos que não tocam a borda esquerda (indentação alinhada ao texto).