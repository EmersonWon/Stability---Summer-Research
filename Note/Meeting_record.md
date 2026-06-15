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

### 26.6.15 
#### Main topic 
- Our later focus is section 3.1 in `main.tex` 
- PCR: learn $U$ from $X$ (PCA); regress $Y$ on $U^\top X$ 
- Features selection: Regress $Y$ on $X_{:,S}$, or in the form $U^\top X$ where $U$ only consists of $0,1$ 
- The **theorem** of these example would be written by Prof. Zheng, and once it's done I need to go through it 
#### Task 
- Polish the proof and add it to the file `proof.tex`, which would be automatically added into `main.tex` 
- Summarize the paper having been read, and add it to `literature.tex` 
- Read *Building a stable classifier with the inflated arg-max* explicitly, whose contents might be of use for later work 
- Check if there's **stochastic** algorithm case, if not (probably for simplicity) try generalizing (cover stochastic algorithm)
- Reach Prof. Zheng next time when ready 

#### Skills and experience 
- *Ranking* Prop5: such a statement about opimimality is more like a specific case (depends on what you need) 
- This paper (*Ranking*) cares only about **deterministic** algorithms, it's probably because most ranking methods are deterministic 
- In what cases stochastic algorithms are included: SGD, resampling, etc. 

