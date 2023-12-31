% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/main.R
\name{pareg}
\alias{pareg}
\title{Pathway enrichment using a regularized regression approach.}
\usage{
pareg(
  df_genes,
  df_terms,
  lasso_param = NA_real_,
  network_param = NA_real_,
  term_network = NULL,
  cv = FALSE,
  cv_cores = NULL,
  family = beta,
  response_column_name = "pvalue",
  max_iterations = 1e+05,
  lasso_param_range = seq(0, 2, length.out = 10),
  network_param_range = seq(0, 500, length.out = 10),
  log_level = NULL,
  ...
)
}
\arguments{
\item{df_genes}{Dataframe storing gene names and DE p-values.}

\item{df_terms}{Dataframe storing pathway database.}

\item{lasso_param}{Lasso regularization parameter.}

\item{network_param}{Network regularization parameter.}

\item{term_network}{Term similarity network as adjacency matrix.}

\item{cv}{Estimate best regularization parameters using cross-validation.}

\item{cv_cores}{How many cores to use for CV parallelization.}

\item{family}{Distribution family of response.}

\item{response_column_name}{Which column of model dataframe
to use as response.}

\item{max_iterations}{How many iterations to maximally run optimizer for.}

\item{lasso_param_range}{LASSO regularization parameter search space
in grid search of CV.}

\item{network_param_range}{Network regularization parameter search space
in grid search of CV.}

\item{log_level}{Control verbosity (logger::INFO, logger::DEBUG, ...).}

\item{...}{Further arguments to pass to `(cv.)edgenet`.}
}
\value{
An object of class \code{pareg}.
}
\description{
Run model to compute pathway enrichments.
 Can model inter-pathway relations, cross-validation and much more.
}
\examples{
df_genes <- data.frame(
  gene = paste("g", 1:20, sep = ""),
  pvalue = c(
    rbeta(10, .1, 1),
    rbeta(10, 1, 1)
  )
)
df_terms <- rbind(
  data.frame(
    term = "foo",
    gene = paste("g", 1:10, sep = "")
  ),
  data.frame(
    term = "bar",
    gene = paste("g", 11:20, sep = "")
  )
)
pareg(df_genes, df_terms, max_iterations = 10)
}
