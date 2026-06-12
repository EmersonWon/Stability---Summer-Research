# Meeting Notes and Record

... 

### 26.5.21 
#### Main topic
- Bagging situation: $\mathrm{Average(SGD}(\theta_0;Z_I))$, here $I$ is a subset of $[N]$, and $\theta_0$ uses all data information
- Hardness: stability of bagging is not applicable here due to $\theta_0$; 
- More precisely, the procedure follows by: 
  - Step1: obtain $\theta_0$ through SGD on all data; 
  - Step2: run SGD locally on each $Z_I$, starting from $\theta_0$; 
  - Step3: Average local SGD outputs over all subsets $I$.
- In general, assume $g=f_k\circ f_{k-1}\circ \cdots\circ f_1$, given stability of $f_1,\cdots,f_k$, we are interested in the stability of $g$. 
#### Task 
- Read 2 papers, go through the proofs and write a proof sketch (both are in the file)
- Read [another paper](https://arxiv.org/pdf/2601.11701) for interst
#### Skills and Experience
- 

### 26.6.8
#### Task
- Try to prove the theorem in `main.tex` 
- Do extra reading, see `literature.tex` 
#### Skills and Experience
- Find out which paper to read among the references: check the most cited one (classic); see the *related work* section of new ones to see their positions and relations
- Organize what you have done, see the structures in **Overleaf** 
