import sys
import pandas as pd

from bioinf_common.algorithms import SetEnrichmentComputer

from utils import Executor


class MyExecutor(Executor):
    def setup(self):
        threshold = .05

        self.genes = set(
            self.df_inp.loc[self.df_inp['p_value'] < threshold, 'gene']
                       .tolist()
        )
        self.grouping = (self.df_terms.groupby('term')['gene']
                                      .apply(set)
                                      .to_dict())

    def execute(self):
        sec = SetEnrichmentComputer(
            self.grouping, self.reference_set,
            alternative_hypothesis='two-sided')
        res = sec.get_terms(self.genes)

        self.df_result = (res[['group_name', 'p_value']]
                          .rename(columns={'group_name': 'term'})
                          .copy())


if __name__ == '__main__':
    ex = MyExecutor(sys.argv[1], sys.argv[2])
    ex.run()
