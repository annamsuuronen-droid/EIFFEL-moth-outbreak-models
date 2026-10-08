"""Small arithmetic tests; no scientific datasets fabricated or published."""
import importlib.util
import math
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('assessment',Path(__file__).parents[1]/'assess_model_readiness_v1.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class ReadinessArithmetic(unittest.TestCase):
    def fixture(self):
        return [dict(observed=str(y),predicted_median=str(p),presence_probability=str(prob)) for y,p,prob in [(0,0,.1),(1,2,.6),(4,3,.9)]]
    def test_known_metrics(self):
        d=m.diagnostics(self.fixture())
        self.assertAlmostEqual(d['RMSE'],math.sqrt(2/3))
        self.assertAlmostEqual(d['O.AUC'],1)
        self.assertEqual(d['n'],3);self.assertEqual(d['zeros'],1)
        self.assertAlmostEqual(d['largest_error_SSE_fraction'],.5)
    def test_missing_outcome_fails_closed(self):
        f=self.fixture();f[0]['observed']='NA'
        with self.assertRaises(AssertionError):m.diagnostics(f)
    def test_close_missing(self):
        self.assertTrue(m.close('NA',math.nan));self.assertFalse(m.close(0,math.nan))
    def test_corrupt_metric_detected(self):
        self.assertFalse(m.close(m.diagnostics(self.fixture())['RMSE'],999))

if __name__=='__main__':unittest.main()
