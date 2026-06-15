## Note for *Assumption-free stability for ranking problems* 

### Information 
- Author: 

### 1. Introduction 
- Existing challenges: the output ranking list is often sensitive to slight perturbations of training data 
- Goal: methods to solve top-k selection and full-ranking 

#### 1.1 Problem setting 
- Given a list of $L$ items and a mechanism for estimating the scores, seek to select the top-$k$ items or rank the full 
- Process of 2 stages: 
  1. $\mathcal{D}=\{Z_1,\cdots,Z_n\} $ is the dataset, and run $\mathcal{A}$ to achieve the scores $\hat{w}=(\hat{w}_1,\cdots,\hat{w}_L)$ 
  2. Either sort them or select the top-$k$ items 
- Though Step 1 might be stable, the final output can still be susceptible to slight changes, for a ranking operation is discontinuous 
- 

