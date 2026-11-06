"""Safe model format: a decision tree as plain JSON, evaluated in pure Python (no pickle, no scikit-learn at run time).
Schema: {"format": "tactile-tree-v1", "features": [...], "classes": [...], "left": [...], "right": [...], "feature": [...],
         "threshold": [...], "leaf_class": [...]}   (parallel arrays, node 0 is the root, left == -1 marks a leaf).
sklearn evaluates `float32(x) <= threshold` (threshold is float64); predict() reproduces that exactly."""
import json, struct

FORMAT = "tactile-tree-v1"

def _f32(x): return struct.unpack("f", struct.pack("f", float(x)))[0]

def export_tree(clf, features, classes):
    T = clf.tree_
    return dict(format=FORMAT, features=list(features), classes=[int(c) for c in classes],
                left=[int(v) for v in T.children_left], right=[int(v) for v in T.children_right], feature=[int(v) for v in T.feature],
                threshold=[float(v) for v in T.threshold], leaf_class=[int(classes[int(v.argmax())]) for v in T.value[:, 0, :]])

class TreeModel:
    def __init__(self, d):
        if not isinstance(d, dict) or d.get("format") != FORMAT: raise ValueError("not a %s model" % FORMAT)
        n = len(d["left"])
        for k in ("right", "feature", "threshold", "leaf_class"):
            if len(d[k]) != n: raise ValueError(f"array '{k}' has the wrong length")
        nf = len(d["features"])
        for i in range(n):
            l, r = d["left"][i], d["right"][i]
            if l == -1:
                if r != -1: raise ValueError("leaf with a right child")
            else:
                if not (i < l < n and i < r < n): raise ValueError(f"node {i}: children must be later nodes inside the tree (no cycles)")
                if not (0 <= d["feature"][i] < nf): raise ValueError(f"node {i}: feature index out of range")
        self.d, self.n_features = d, nf

    @classmethod
    def load(cls, path):
        with open(path) as fh: return cls(json.load(fh))

    def predict_one(self, x):
        d = self.d
        if len(x) != self.n_features: raise ValueError(f"expected {self.n_features} features, got {len(x)}")
        n = 0
        while d["left"][n] != -1: n = d["left"][n] if _f32(x[d["feature"][n]]) <= d["threshold"][n] else d["right"][n]
        return d["leaf_class"][n]

    def predict(self, X): return [self.predict_one(x) for x in X]
