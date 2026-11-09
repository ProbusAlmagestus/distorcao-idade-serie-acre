# =====================================================================
#  Distorção idade-série nas escolas da rede estadual do Acre
#  Análise descritiva com dados abertos do INEP
#
#  Autor: Eduardo — Tecnologia em Ciência de Dados (Gran Faculdade)
#  Projeto Integrador — 3º período
#
#  COMO USAR ESTE ARQUIVO
#  - Abra no RStudio.
#  - Rode um bloco de cada vez: selecione as linhas e aperte Ctrl + Enter.
#  - Tudo que começa com "#" é comentário: o R ignora, serve para você ler.
# =====================================================================


# ---------------------------------------------------------------------
# PASSO 0 — Carregar os pacotes
# ---------------------------------------------------------------------
# Pacotes são "caixas de ferramentas" que ampliam o R.
#   readxl  -> lê planilhas do Excel (.xlsx)
#   dplyr   -> filtra, seleciona e resume tabelas
#   tidyr   -> reorganiza tabelas (de "largo" para "longo")
#   ggplot2 -> faz gráficos
# As linhas abaixo instalam só o que estiver faltando (na 1ª vez demora).

pacotes <- c("readxl", "dplyr", "tidyr", "ggplot2")
faltando <- pacotes[!pacotes %in% rownames(installed.packages())]
if (length(faltando) > 0) install.packages(faltando)

library(readxl)
library(dplyr)
library(tidyr)
library(ggplot2)

# Cria as pastas onde vamos salvar resultados e gráficos (se não existirem)
dir.create("resultados", showWarnings = FALSE)
dir.create("graficos",   showWarnings = FALSE)


# ---------------------------------------------------------------------
# PASSO 1 — Ler o arquivo do INEP
# ---------------------------------------------------------------------
# O arquivo baixado do INEP deve estar na pasta "dados".
# O comando abaixo procura sozinho a planilha (.xlsx) dentro dessa pasta.

arquivo <- list.files("dados", pattern = "\\.xlsx$",
                      full.names = TRUE, ignore.case = TRUE)[1]

if (is.na(arquivo)) {
  stop("Não achei o arquivo do INEP na pasta 'dados'. Veja o README, seção 'Como reproduzir'.")
}
print(arquivo)

# Como é a planilha do INEP (confira abrindo no Excel):
#   - no topo, o logotipo e linhas de título;
#   - depois, um quadro com cabeçalho em DUAS linhas: na 1ª, "Ano", "Região",
#     "UF"... e os grupos "Ensino Fundamental" e "Ensino Médio"; na 2ª, as
#     subdivisões ("Total", "Anos Iniciais", "Anos Finais", "1º Ano"...);
#   - por fim, uma linha por escola do Brasil.
# Por isso lemos a planilha SEM nomes de coluna (col_names = FALSE) e damos
# nós mesmos os nomes, pela posição de cada coluna.
# col_types = "text": lemos tudo como texto, porque o INEP usa "--" quando
# não há dado, e isso atrapalharia a leitura dos números.

planilha <- read_excel(arquivo, col_names = FALSE, col_types = "text",
                       .name_repair = "minimal")

# As linhas de escola são as que têm um ano (4 algarismos) na 1ª coluna.
# Assim descartamos títulos, cabeçalhos e notas de rodapé de uma vez.
eh_escola <- grepl("^[0-9]{4}$", planilha[[1]])
dados_brutos <- planilha[eh_escola, ]

# Conferência: a linha do cabeçalho deve mostrar "Ano", "Região", "UF"...
linha_cabecalho <- which(planilha[[1]] == "Ano")[1]
print(unlist(planilha[linha_cabecalho, 1:9]))

# O quadro deve ter 26 colunas. Se tiver outro número, o INEP mudou o
# formato: compare com o print do Excel antes de seguir.
if (ncol(dados_brutos) != 26) {
  stop("A planilha tem ", ncol(dados_brutos), " colunas, e o script espera 26. Veja 'Problemas comuns' no guia.")
}

# Nomes das 26 colunas, na ordem em que aparecem no quadro do INEP
names(dados_brutos) <- c(
  "ano", "regiao", "uf", "cod_municipio", "municipio",
  "cod_escola", "escola", "localizacao", "rede",
  "fund_total", "fund_anos_iniciais", "fund_anos_finais",
  paste0("fund_", 1:9, "ano"),        # fund_1ano ... fund_9ano
  "medio_total",
  paste0("medio_", 1:4, "serie")      # medio_1serie ... medio_4serie
)

# Primeiras olhadas na tabela:
dim(dados_brutos)        # número de linhas (escolas) e de colunas (26)
head(dados_brutos)       # primeiras 6 linhas


# ---------------------------------------------------------------------
# PASSO 2 — Filtrar: só Acre e só a rede estadual
# ---------------------------------------------------------------------
# O operador |> (lê-se "e então") passa o resultado para o próximo comando.

table(dados_brutos$rede)   # quais redes existem no arquivo e quantas escolas

# O sinal == (dois iguais) testa se o valor é igual ao texto indicado.
acre <- dados_brutos |>
  filter(uf == "AC",
         rede == "Estadual")

nrow(acre)   # quantas escolas estaduais do Acre ficaram
table(acre$localizacao)   # quantas são urbanas e quantas são rurais


# ---------------------------------------------------------------------
# PASSO 3 — Limpar: transformar as taxas em números
# ---------------------------------------------------------------------
# Vamos estudar três etapas de ensino (colunas "Total" de cada grupo):
#   fund_anos_iniciais -> Ensino Fundamental, anos iniciais (1º ao 5º ano)
#   fund_anos_finais   -> Ensino Fundamental, anos finais (6º ao 9º ano)
#   medio_total        -> Ensino Médio
# Esta função troca "--" por vazio (NA), troca vírgula por ponto
# e converte o texto em número.

para_numero <- function(x) {
  x[x %in% c("--", "-", "")] <- NA
  as.numeric(gsub(",", ".", x))
}

acre <- acre |>
  mutate(
    ano               = as.integer(ano),
    tdi_anos_iniciais = para_numero(fund_anos_iniciais),
    tdi_anos_finais   = para_numero(fund_anos_finais),
    tdi_medio         = para_numero(medio_total)
  ) |>
  select(ano, cod_escola, escola, municipio, rede, localizacao,
         tdi_anos_iniciais, tdi_anos_finais, tdi_medio)

summary(acre)   # resumo rápido de cada coluna

# Guardamos a base já filtrada (é pequena e pode ir para o GitHub)
write.csv2(acre, "dados/tdi_escolas_estaduais_acre.csv", row.names = FALSE)


# ---------------------------------------------------------------------
# PASSO 4 — Reorganizar a tabela para o formato "longo"
# ---------------------------------------------------------------------
# Hoje cada escola tem 3 colunas de taxa (uma por etapa). Para comparar as
# etapas, é mais prático ter uma linha por "escola + etapa".
# Escolas que não oferecem a etapa ficam vazias (NA) e são retiradas.

acre_longo <- acre |>
  pivot_longer(cols = starts_with("tdi_"),
               names_to = "etapa", values_to = "tdi") |>
  filter(!is.na(tdi)) |>
  mutate(etapa = factor(etapa,
                        levels = c("tdi_anos_iniciais", "tdi_anos_finais", "tdi_medio"),
                        labels = c("Fund. anos iniciais", "Fund. anos finais", "Ensino médio")))

head(acre_longo)


# ---------------------------------------------------------------------
# PASSO 5 — Medidas descritivas
# ---------------------------------------------------------------------
# Para cada etapa calculamos:
#   n        -> quantas escolas têm dado
#   média    -> soma dividida pela quantidade
#   mediana  -> valor do meio (metade das escolas abaixo, metade acima)
#   desvio-padrão (dp) -> quanto as taxas se afastam, em média, da média
#   CV       -> coeficiente de variação = dp / média (em %): dispersão relativa
#   Q1 e Q3  -> 25% e 75% das escolas estão abaixo desses valores
#   assimetria -> > 0: cauda à direita (algumas escolas com taxas bem altas)
#                 < 0: cauda à esquerda;  perto de 0: distribuição simétrica

assimetria <- function(x) {
  m <- mean(x); s <- sd(x)
  mean((x - m)^3) / s^3
}

resumo_etapas <- acre_longo |>
  group_by(etapa) |>
  summarise(
    n_escolas  = n(),
    media      = mean(tdi),
    mediana    = median(tdi),
    desvio_pad = sd(tdi),
    cv_pct     = 100 * sd(tdi) / mean(tdi),
    minimo     = min(tdi),
    q1         = quantile(tdi, 0.25),
    q3         = quantile(tdi, 0.75),
    maximo     = max(tdi),
    assimetria = assimetria(tdi)
  ) |>
  mutate(across(where(is.numeric) & !n_escolas, ~ round(.x, 1)))

print(resumo_etapas)
write.csv2(resumo_etapas, "resultados/resumo_por_etapa.csv", row.names = FALSE)

# Mesmo resumo, separado por localização (urbana x rural)
resumo_localizacao <- acre_longo |>
  group_by(etapa, localizacao) |>
  summarise(n_escolas = n(),
            media = round(mean(tdi), 1),
            mediana = round(median(tdi), 1),
            desvio_pad = round(sd(tdi), 1),
            .groups = "drop")

print(resumo_localizacao)
write.csv2(resumo_localizacao, "resultados/resumo_por_localizacao.csv", row.names = FALSE)

# Mediana por município nos anos finais do fundamental
resumo_municipio <- acre_longo |>
  filter(etapa == "Fund. anos finais") |>
  group_by(municipio) |>
  summarise(n_escolas = n(),
            mediana = round(median(tdi), 1),
            media   = round(mean(tdi), 1)) |>
  arrange(desc(mediana))

print(resumo_municipio, n = 30)
write.csv2(resumo_municipio, "resultados/resumo_por_municipio_anos_finais.csv", row.names = FALSE)


# ---------------------------------------------------------------------
# PASSO 6 — Gráficos
# ---------------------------------------------------------------------
# ggplot funciona em camadas, somadas com "+":
#   ggplot(dados, aes(...))  -> diz quais dados e quais variáveis
#   geom_...()               -> diz o tipo de gráfico
#   labs()                   -> títulos e rótulos

ano_dados <- max(acre$ano, na.rm = TRUE)
fonte <- paste0("Fonte: INEP — Indicadores Educacionais, TDI por escola (", ano_dados, ")")

# 6.1 Histograma: como as taxas se distribuem entre as escolas?
g1 <- ggplot(acre_longo, aes(x = tdi)) +
  geom_histogram(binwidth = 5, fill = "#2c7fb8", color = "white") +
  facet_wrap(~ etapa, ncol = 1) +
  labs(title = "Distorção idade-série nas escolas estaduais do Acre",
       subtitle = "Quantidade de escolas em cada faixa de taxa (faixas de 5 pontos)",
       x = "Taxa de distorção idade-série (%)", y = "Número de escolas",
       caption = fonte) +
  theme_minimal()
print(g1)
ggsave("graficos/01_histograma_por_etapa.png", g1, width = 8, height = 8, dpi = 150)

# 6.2 Boxplot por etapa: compara mediana, quartis e valores extremos
# Leitura do boxplot: a linha do meio é a mediana; a caixa vai de Q1 a Q3;
# os pontos soltos são escolas com taxas muito diferentes das demais.
g2 <- ggplot(acre_longo, aes(x = etapa, y = tdi)) +
  geom_boxplot(fill = "#a6bddb") +
  labs(title = "Distorção idade-série por etapa — rede estadual do Acre",
       x = NULL, y = "Taxa de distorção idade-série (%)", caption = fonte) +
  theme_minimal()
print(g2)
ggsave("graficos/02_boxplot_por_etapa.png", g2, width = 8, height = 5, dpi = 150)

# 6.3 Boxplot por localização (urbana x rural), em cada etapa
# Confira o n_escolas em resumo_localizacao: uma caixa feita com poucas
# escolas deve ser lida com cautela.
g3 <- ggplot(acre_longo, aes(x = localizacao, y = tdi)) +
  geom_boxplot(fill = "#a6bddb") +
  facet_wrap(~ etapa) +
  labs(title = "Distorção idade-série por localização — rede estadual do Acre",
       x = NULL, y = "Taxa de distorção idade-série (%)", caption = fonte) +
  theme_minimal()
print(g3)
ggsave("graficos/03_boxplot_por_localizacao.png", g3, width = 10, height = 5, dpi = 150)

# 6.4 Barras: mediana por município (anos finais)
g4 <- ggplot(resumo_municipio,
             aes(x = mediana, y = reorder(municipio, mediana))) +
  geom_col(fill = "#2c7fb8") +
  geom_text(aes(label = format(mediana, decimal.mark = ",")),
            hjust = -0.15, size = 3) +
  labs(title = "Mediana da TDI por município — anos finais, rede estadual do Acre",
       x = "Mediana da taxa (%)", y = NULL, caption = fonte) +
  theme_minimal()
print(g4)
ggsave("graficos/04_mediana_por_municipio_anos_finais.png", g4, width = 8, height = 7, dpi = 150)


# ---------------------------------------------------------------------
# PASSO 7 — Frases de apoio para a interpretação
# ---------------------------------------------------------------------
# O R escreve algumas frases com os seus resultados. Use-as como ponto de
# partida para a seção "Resultados" do README (revise com suas palavras).

for (i in seq_len(nrow(resumo_etapas))) {
  r <- resumo_etapas[i, ]
  forma <- if (r$assimetria > 0.5) "assimétrica à direita (algumas escolas com taxas bem acima das demais)" else
    if (r$assimetria < -0.5) "assimétrica à esquerda" else "aproximadamente simétrica"
  cat(sprintf(
    "\n- %s: %d escolas. Média de %.1f%% e mediana de %.1f%%; metade das escolas fica entre %.1f%% e %.1f%%. Desvio-padrão de %.1f pontos (CV de %.0f%%). Distribuição %s.\n",
    r$etapa, r$n_escolas, r$media, r$mediana, r$q1, r$q3, r$desvio_pad, r$cv_pct, forma))
}

# Fim do script. Os gráficos estão na pasta "graficos" e as tabelas em "resultados".