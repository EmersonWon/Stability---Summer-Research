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

### 26.7.24 
#### Main topic
- Future plan: Ph.D. still can help you gain experience, and for broad study (rather than depth in Bachelor period) 
- Possible programs to apply for: AI-related, like safety, interpretability and connections to fields that's not so developed as AI4M(like bio) 
- AI works better in a closed framework. If you let AI arrange everything, it can give you a boring topic to work on (meaningless) 
- Later in this project: case-led, work on the feature selection/screening first, not PCA(not worth trying) 
#### Task 
- Check if there's anything wrong with **Theorem 1**, and delete the *(to be proved)* label 
- Go over the new related paper about stability recently published 
- Check the feature selection part when added (1 or 2 days later) 
#### Skills and experience 
- Sometimes we would use asymptotic analysis to express a conclusion explicitly, as a compromise to condition 

### 26.7.31
#### Main topic 
- Recent problems: the matrix I constructed is not typical enough, since we hope the samples are i.i.d. (each is close) 
- Prof. Zheng has an idea (with *orthogonal* design, the $\hat{\beta}$ would be $\rho_{X^{(j)},Y}\mathbf{1}\{j\in S\}$), but not explicit enough (covariance would change after LOO). But we could still try (focus on the set $S\Delta S^{\setminus k}, $) 
- Note that the first step (variance filter) has nothing to do with $Y$ (*unsupervised learning*), so we could construct $X$ first to get $|S\Delta S^{\setminus k}|\ge $, then select an appropriate $Y$ to surfice $|\rho_{X^{(j)},Y}|>\varepsilon$
- The current metric has its disadvantages, so we have several alternatives: 
  - We prove that $\exist P_{(X,Y)}$ and $(X_i,Y_i)\mathrm{i.i.d.}\sim P$ (for simplicity, we could start from $X\sim N(0,I_p)$ and $Y=X\beta^*+\varepsilon$) and define a metric $$d(\beta^{(1)},\beta^{(2)})=\sqrt{\sum_{k=1}^p(\beta_j^{(1)}-\beta_j^{(2)})\frac{\mathrm{Var}(X_j)}{\mathrm
  {Var}(Y)}}$$ (intuition: $\hat{\beta}\sqrt{\frac{\mathrm{Var}(X_j)}{\mathrm{Var}(Y)}}\approx \rho_{X_j,Y}$, which is population correlation), then we hope 
  - The one more likely to succeed: $\forall \tau>0,\varepsilon\in (0,1), X$(full rank), $\exist c>0, Y\in \mathbb{R}^N$ s.t. $\mathcal{A}(cX,Y)$ is not $(\varepsilon, 1/2)$-stable. One possible path is to choose $c=\widehat{\mathrm{Var}}(X^{(j)})$ and $Y$ s.t. $\widehat{\rho}_{X^{(j)},Y}>\varepsilon $ 
- A possible later procedure: we view the current procedure as multiplying by a indicator vector $Z\in \mathbb{R}^M$, $z_j\in \{0,1\}$; we could later exchange it with $z_j\in [0,1]$ to smooth it 
- Others: my idea: other kinds of outputs followed by a similar *second-step* procedure like ranking. The problem is that we care about whether the inference is *valid* and *powerful* enough, but stability rarely plays a role (an estimated interval, $p$-value) 
#### Task 
- Check explicitly the alternative path mentioned above 

### 26.8.7 
#### Main topic 
- Since it's difficult to find an exact or moderate condition needed for instability of *feature selection + linear regression*, we would rather pause here and consider the opposite: we propose a method called **soft selection**, and will try proving its properties(stability, lower bound) 
- Prof. Zheng had a result about the instability of the *population-case*, but we won't need it if the result above works well (the result would require conditions like $\varepsilon^2 \delta\ge\frac{1}{\sqrt{n}}$)
- Since we get the predictor through $\hat{f}(x)=\frac{1}{B}\sum_{b=1}^Bx_{S^{(b)}}^\top \hat{\beta}_{S^{(b)}}^{(b)}$, we could measure the stability using the former metric on $\hat{\beta}=\frac{1}{B}\sum_{b=1}^B\hat{\beta}_{S^{(b)}} $; or trying stability of $\hat{f}(x)$ instead 
- If showing tail stability is hard, try replacing $\mathbb{P}_\xi$ by $\mathbb{P}_{\xi ,\mathcal{D}}$ (e.g. Gaussian) where $Z_1,\cdots,Z_n\overset{i.i.d.}{\sim}\mathcal{P}$ 
- I find it not good enough if we only show the orthogonal case works, because generalizing could be tough and in $p>n$ cases the orthogonal design does not exist. To cope with it, we could exchange linear regression with **oracle prediction** 
- We would convert some examples that we were to dig into, for we need to concentrate our intuition in a paper 
#### Task 
- Wait until the framework is formalize and try proving the upper bound(stability) 

### 26.8.17
#### Main topic 
- For the lack of availbility, we change the notion of stability from **tail** to **mean-square** 
- The tail stability regarding arbitary parameters is accessible for bagged algorithm, so no worry 
#### Task 
- Convert the theorem from *tail* version to *mean-square* version 

### 26.8.21 
#### Main topic 
- Since the proof has been completed (Thm.3 cannot be reached, thus deleted), the next step would be some experiments 
- Also consider some generalizations of the whole stabilization framework 
#### Task
- Simulation (follow the pilot study)

### 26.9.1 
#### Main topic
- Simulation not done yet, so keep running (the fast part first) 
- We here formalize the 2 implementations, and hope to check their stability 
- About the thesis: upload the information 
#### Task 
- Complete the simulations 
- Try the theory part 

### 26.9.14
#### Main 
- The figures given by ChatGPT are not good enough to show the stability across 10 replicates 
- We plan to give up Implementation I, since it takes average over too many seeds (not fair and efficient) 
- I asked questions about seeds reservation to restrict the randomization 
#### Task 
- Try new simulations (250 trees -> 1000 trees) 
- Develop the figure outputs (better comparison) 
- Complete the proof of Thm 4 
- Small trials about fixing seeds in random forest 

### 26.9.27 
#### Main 
- The figures are shown. But the results of setting 2 and 3 were a bit similar, which may be fair; but still needs checking 
- Configure the figures, the x-axis should be uniform 
- About the *mean-square(sd)* plot, should enlarge the title and specify the subtitle 
- Consider other forms of screening like *sure independence screening* 
- Our further goal is to generalise such screenings. We hope to summarise all these **scores** and their properties 
#### Task 
- Adjust the figures format, complete the proof 
- Read more about other screening methods 

### 26.10.1
#### Main 
- Need to update the figures a little bit more (log-scale, expand the left part of x-axis) 
- Talking about the generalization of our current work (which I had misunderstood)
- Explain the details that need to be improved in the proof (notation, completion, etc) 
#### Task
- Remake the figures 
- Update the existing proofs 
- Wait until the new formulation and add new proofs 

### 26.10.8
#### Main
- Some updates about my work (within those proofs) 
- The proof of Prop 1 may not be optimal (correlation) 
- The figures need a new turn to polish 
- Our next step: PCA stablizer (same mind: smooth the CDF) 
- Possible simulation about the correlation stablizer 
#### Task
- Polish the proofs (Thm 3 statement, Cor 1 C', Thm 4 expectation) 
- The definition of sample variance and correlation could be specified (Pearson, unbiased) 
- Update the figures 
- Try the simulation of correlation, using the dense setting (but alter the selection of $V_j$) 

### 26.10.15 
#### Main 
- Talk about the simulation: about the *mean(SD)* plot, the title should be deleted and the font should be enlarged 
- The $\tau$ in correlation simulation could be updated, for a better choice 
- These figures could be put in the **Empirical study** section (specify the setting) 
- About the theoretical part, there are something I can update: text before the introduction of the **Assumption 1** 
#### Task 
- Adjust the last version of the *mean(SD)* plots 
- Retry the simulation of correlation filter 
- Put the figures in the document 

### 26.10.23 
#### Main 
- Update some new work of mine (word introduction of the *Assumption* and the *Simulation Setting*) 
- Talk about the notation of a random bag ($r_b\to D_b$) 
- The order of the introduction of the Simulation Setting (data generating process) should be revised 
- Three parts: data generating models, algorithms used including the baselines, measure of stability 
- Check the simulation results together and try to explain (2-step stability, each stability) 
- I mentioned the failure of *SIS simulation* and the choice of $\nu$ (data-driven?) 
- The first setting's result was no that obvious, for the model itself is too simple (even hard screening did well) 
- Review the **Thm 3** to see that $\nu$ plays a vital role in the stability rather than $\tau$ 
- We may need to check the stability of the first step of the whole algorithm, namely $\mathcal A^{(1)}$ 
