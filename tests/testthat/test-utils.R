test_that("model creation works with only common genes", {
  df_genes <- data.frame(
    gene = c("g1", "g2"),
    pvalue = c(0.01, 0.2)
  )
  df_terms <- data.frame(
    term = c("A", "A", "B", "B", "C"),
    gene = c("g1", "g2", "g1", "g2", "g2")
  )

  df_res <- create_model_df(df_genes, df_terms)
  df_expected <- tibble(
    gene = as.factor(c("g1", "g2")),
    pvalue = c(0.01, 0.2),
    A.member = c(TRUE, TRUE),
    B.member = c(TRUE, TRUE),
    C.member = c(FALSE, TRUE),
    pvalue_sig = c(TRUE, FALSE),
    pvalue_notsig = c(FALSE, TRUE)
  )

  expect_equal(df_res, df_expected)
})


test_that("model creation works with gene which is in no term", {
  df_genes <- data.frame(
    gene = c("g1", "g2", "g3"),
    pvalue = c(0.01, 0.2, 0.3)
  )
  df_terms <- data.frame(
    term = c("A", "A", "B", "B", "C"),
    gene = c("g1", "g2", "g1", "g2", "g2")
  )

  df_res <- create_model_df(df_genes, df_terms)
  df_expected <- tibble(
    gene = as.factor(c("g1", "g2", "g3")),
    pvalue = c(0.01, 0.2, 0.3),
    A.member = c(TRUE, TRUE, FALSE),
    B.member = c(TRUE, TRUE, FALSE),
    C.member = c(FALSE, TRUE, FALSE),
    pvalue_sig = c(TRUE, FALSE, FALSE),
    pvalue_notsig = c(FALSE, TRUE, TRUE)
  )

  expect_equal(df_res, df_expected)
})


test_that("similarity sampling works", {
  cluster_sizes <- c(5, 5, 10, 10, 10)
  sim_mat <- generate_similarity_matrix(cluster_sizes)

  df_sims <- rep(c(1, 0.5, 0), each = 10) %>%
    purrr::map_dfr(function(w) {
      selected_samples <- pareg::similarity_sample(
        sim_mat,
        size = 10,
        similarity_factor = w
      )
      similarity_values <- sim_mat[selected_samples, selected_samples]
      data.frame(
        w = w,
        similarity_values = as.vector(unname(unlist(similarity_values)))
      )
    })

  df_sims %>%
    head()

  ggplot(df_sims, aes(x = as.factor(w), y = similarity_values)) +
    geom_boxplot() +
    theme_minimal()

  grp_mean <- df_sims %>%
    group_by(w) %>%
    summarize(mean = mean(similarity_values))
  grp_mean

  expect_lt(grp_mean[1, 2], grp_mean[2, 2])
  expect_lt(grp_mean[2, 2], grp_mean[3, 2])
})


test_that("enrichplot integration works", {
  skip_on_os("windows") # not a great fix

  # create synthetic data
  set.seed(42)

  df_genes <- data.frame(
    gene = paste("g", 1:25, sep = ""),
    pvalue = c(
      rbeta(10, .1, 1),
      rbeta(15, 1.1, 1)
    )
  )

  df_terms <- rbind(
    data.frame(
      term = "foo",
      gene = paste("g", 1:12, sep = "")
    ),
    data.frame(
      term = "bar",
      gene = paste("g", 11:25, sep = "")
    ),
    data.frame(
      term = "baz",
      gene = paste("g", 21:25, sep = "")
    )
  )

  # run model
  res <- pareg(df_genes, df_terms, max_iteration = 10)

  # test integration
  obj <- as_enrichplot_object(res)

  enrichplot::cnetplot(obj)
  enrichplot::dotplot(obj) +
    scale_colour_continuous(name = "Enrichment Score")
  expect_equal(
    obj@result[c("foo", "bar", "baz"), ]$GeneRatio,
    c("9/12", "2/15", "0/5")
  )

  obj <- enrichplot::pairwise_termsim(obj)
  expect_equal(obj@termsim["foo", "baz"], 0)
  expect_equal(obj@termsim["bar", "foo"], 0.08)
  expect_equal(obj@termsim["bar", "baz"], 0.33333333)

  enrichplot::emapplot(obj, min_edge = 0) +
    scale_fill_continuous(name = "Enrichment Score")
  # enrichplot::treeplot(obj, nCluster = 2) +
  #   scale_colour_continuous(name = "Enrichment Score")
})


test_that("tensorflow integration works", {
  cl <- basiliskStart(
    pareg_env,
    testload = c("tensorflow", "tensorflow_probability")
  )
  versions <- basiliskRun(cl, function() {
    list(
      tf_version = tensorflow::tf$version$VERSION,
      tfp_version = tfprobability::tfp$`__version__`
    )
  })
  basiliskStop(cl)

  expect_equal(versions$tf_version, "2.10.0")
  expect_equal(versions$tfp_version, "0.14.0")
})
