library(tidyverse)
library(magrittr) # for %<>%
library(msigdbr)


# parameters
fname_out <- snakemake@output$fname

term_filter_params <- snakemake@params$term_filter
termsource <- snakemake@wildcards$termsource

parts <- strsplit(termsource, "@")[[1]]

# setup
set.seed(42)

# generate base term set
if (parts[[1]] == "msigdb") {
  category <- parts[[2]]
  subcategory <- parts[[3]]

  # overview (http://www.gsea-msigdb.org/gsea/msigdb/collections.jsp)
  msigdbr_species()
  msigdbr_collections() %>%
    arrange(desc(num_genesets))
  msigdbr_collections() %>%
    group_by(gs_cat) %>%
    summarize(num_genesets = sum(num_genesets)) %>%
    arrange(desc(num_genesets))

  # retrieve terms
  df_terms <- msigdbr(species = "Homo sapiens")

  # subset terms
  df_terms <- df_terms %>%
    filter(gs_cat == category) %>%
    {
      if (subcategory != "None") {
        print("Filtering subcategory")
        filter(., gs_subcat == subcategory)
      } else {
        print("Skipping subcategory filter")
        .
      }
    } %>%
    select(gs_exact_source, gene_symbol) %>% # gs_name
    rename(term = gs_exact_source, gene = gene_symbol) %>%
    distinct(.keep_all = TRUE) %>%
    mutate(
      term = str_replace_all(term, ":", "_")
    )
} else if (parts[[1]] == "custom") {
  group_num <- as.numeric(parts[[2]])
  group_size <- as.numeric(parts[[3]])
  pathways_from_group <- as.numeric(parts[[4]])

  gene_count <- 10

  gene_groups <- purrr::map(seq(1, group_num), function(group_idx) {
    glue::glue("g{group_idx}_gene_{seq(1, group_size)}")
  })
  genes_bg <- paste0("bg_gene_", seq(1, 10000))

  if (group_size <= gene_count) {
    warning("Group size smaller than/equal sample size, no randomness")
  }

  df_terms <- purrr::imap_dfr(
    gene_groups,
    function(current_gene_list, gene_list_idx) {
      purrr::map_dfr(seq(1, pathways_from_group), function(pathway_idx) {
        data.frame(
          term = paste0("g", gene_list_idx, "_term_", pathway_idx),
          gene = c(
            sample(
              current_gene_list,
              min(gene_count, group_size),
              replace = FALSE
            ),
            sample(
              genes_bg,
              min(gene_count, group_size),
              replace = FALSE
            )
          )
        )
      })
    }
  )
} else {
  stop(paste("Unknown term database source:", parts[[1]]))
}

# convert all characters to lower case to improve method compatibility
df_terms <- df_terms %>%
  mutate(
    term = str_to_lower(term),
    gene = str_to_lower(gene)
  )

# select terms of reasonable size
df_term_tally <- df_terms %>%
  group_by(term) %>%
  tally() %>%
  arrange(desc(n))

if (!is.null(term_filter_params$min_size)) {
  print("Filtering pathway by min_size")
  df_term_tally %<>%
    filter(term_filter_params$min_size < n)
}
if (!is.null(term_filter_params$max_size)) {
  print("Filtering pathway by max_size")
  df_term_tally %<>%
    filter(n < term_filter_params$max_size)
}
if (!is.null(term_filter_params$sample_num)) {
  print("Sampling pathways")
  df_term_tally %<>%
    sample_n(min(term_filter_params$sample_num, n()))
}

term_selection <- df_term_tally %>%
  pull(term)
term_selection %>%
  head()

df_sub <- df_terms %>%
  filter(term %in% term_selection)

# data overview
df_sub %>%
  head()

print("Distinct term count:")
df_sub %>%
  distinct(term) %>%
  dim()

print("Genes per term:")
df_sub %>%
  group_by(term) %>%
  tally() %>%
  arrange(desc(n))

# save result
df_sub %>%
  write_csv(fname_out)
