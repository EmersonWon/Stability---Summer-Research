## Note of *Building a stable classifier with the inflated argmax* 


### Information 
- A framework for algorithmic stability in the context of **multiclass classification** (taking maximizer)

### 1. Introduction 
- Application: decision-making, interpretable ML(reproducibility), robustness 
- Setting of multiclass classfication: data's features $X\in \mathcal{X}$, labels $Y\in [L]$ 
- Find the $l\in [L]$ that maximizes $P(Y=l|X) $, i.e. $\hat{y}=\argmax_l \hat{p}_l(x) $ 
- Difference between the stability of those predicted *probabilities* and the predicted *labels* itself 

#### 1.1 Problem setting
- Supervised classfication: data set $\mathcal{D}=((X_i, Y_i))_{i\in [n]} $, train a classifier $\mathcal{X}\to [L]$ 
- Two stages: first learn a map $$\hat{p}\colon \mathcal{X}\to \Delta_{L-1}=\{w\in \mathbb{R}^L\colon \sum_i w_i=1\} $$ and then take the argmax $\hat{y}=\argmax_l\hat{p}_l(x) $ 
- Setbacks: ambiguous situation when more classes achieve the maximum 
- In this framework: learning algorithm $\mathcal{A}$ applied to training data $\mathcal{D}$ to get predicted probabilities $\hat{p}(x)\in \Delta_{L-1} $; by using test features $x\in \mathcal{X}$ and selection rule $s$, get candidate labels $\hat{S}=s(\hat{p}(x))\subset [L]$ 

#### 1.2 Overview of main results 
- Reduce the problem: separately stablize the *learning* and *selection* stages 
- **Def 1** (Inflated argmax): $w\in \mathbb{R}^L$, $$\operatorname{argmax}^\varepsilon(w)\coloneqq \{j\in [L]\colon \mathrm{dist}(w,R_j^{\varepsilon})<\varepsilon \}, $$ here $R_j^\varepsilon=\{w\in \mathbb{R}^L\colon w_j\ge \max_{l\ne j}w_l+\varepsilon/\sqrt{2} \} $. 
- Intuition: This defnition depicts that a small perturbation of $\hat{p}(x)$ would lead to the $j$th probability being the largest 
- Other work that would be included: an algorithm to compute it efficiently; along with bagging can guarantee stability for any classifier 

### 2. Framework: stable classification 
- Define a classification algorithm: $$\mathcal{C}\colon \bigcup_n(\mathcal{X}\times [L])^n\times \mathcal{X}\to 2^{[L]}, $$ where the inputs are the training data and a test feature vector 
- Notation: $\hat{S}=\mathcal{C}(\mathcal{D},x)$ is a candidate set of labels; $\mathcal{C}=s\circ \mathcal{A}$ (see the notation earlier, remember $s$ is the selection rule) 
- As in other papers, we consider leave-one-out stability; but there's still some differences due to the output values 
- **Def 2**(Selection stability): a classification algorithm $\mathcal{C}$ has selection stability $\delta$ at sample size $n$ if for all datasets $\mathcal{D}\in (\mathcal{X}\times [L])^n$ and all $x\in \mathcal{X}$, $$\frac{1}{n}\sum_{i\le n}\mathbf{1}\{\hat{S}\cap \hat{S}^{\setminus i}=\varnothing\}\le \delta $$ where $\hat{S}^{\setminus i}=\mathcal{C}(\mathcal{D}^{\setminus i},x)$. 
#### 2.1 Interpreting the definition 
- The $\hat{S}$ we got: means one of them is the true label $Y$, therefore it's enough even if only *one value* $\in \hat{S}\cap\hat{S}^{\setminus i}$ 
#### 2.2 Connection to classical algorithmic stability 
- Prior work: deal with continuous outputs; so this section connects classical stability with the one here 
- **Def 3**(Tail stability): $\hat{p}=\mathcal{A}(\mathcal{D}), \hat{p}^{\setminus i}=\mathcal{A}(\mathcal{D}^{\setminus i}) $, $$\frac{1}{n}\sum_{i=1}^n\mathbf{1}\{\|\hat{p}(x)-\hat{p}^{\setminus i}(x)\|\ge \varepsilon \}\le \delta $$ 
#### 2.3 From stability to selection stability 
- **Def 4**($\varepsilon$-compatibility): A selection rule $s\colon \Delta_{L-1}\to 2^{[L]} $ satisfying $$\|v-w\|<\varepsilon\implies s(v)\cap s(w)\ne \varnothing. $$ 
- **Prop 5**: Learning algorithm $\mathcal{A}$ has tail stability $(\varepsilon,\delta)$ at $n$, selection rule $s$ has $\varepsilon$-compatibility, then $\mathcal{C}=s\circ \mathcal{A}$ has selection stability $\delta $ at $n$ 
- Due to this we need to focus on compatibility of selection rule $s$; but if it returns the whole $[L]$ for any input, it would be also stable. We need to ensure the output to be *informative* as well 
### 3. Methodology: assumption-free stable classification 
- This section will define the pipeline for a stable classifier using learning algorithm $\mathcal{A}$ 
- Section 3.1 will recall bagged algorithm in *Bagging provides assumption-free stability* 
- Section 3.2 will introduce the *inflated argmax* and establish its $\varepsilon$-compatibility 
- Main theorem: selection guarantee of the procedures; here $\tilde{\mathcal{A}}_m$ denotes a bagged version of $\mathcal{A}$ 
- **Thm 6**: Fix $n,m,\varepsilon>0$, $\forall \mathcal{A}$, $\mathcal{C}=\operatorname{argmax}^{\varepsilon}\circ \tilde{\mathcal{A}}_m$ satisfies selection stability $\delta$. 
#### 3.1 Bagging classifier weights 
- **Def 7**(Bootstrapping or subbagging): $\mathcal{D}=(\mathcal{X}, [L])^n,x\in \mathcal{X} $, output $\tilde{\mathcal{A}}_m=\mathbb{E}_r[\mathcal{A}(\mathcal{D}^r)(x)]$ where the bag $r$ is sampled as in Bootstrapping and Subbagging case 
- **Thm 8**: $\forall \mathcal{A}\colon \mathcal{D}\to \Delta_{L-1}$, its bagged version $\tilde{\mathcal{A}}_m$ has stability $(\varepsilon,\delta)$ for $\delta=\varepsilon^{-2}\cdots$ 
- For computation, $\mathbb{E}_r[\mathcal{A}(\mathcal{D}^r)(x)] $ is computationally infeasible, so we turn to Monte Carlo, using $\tilde{\mathcal{A}}_m(\mathcal{D})(x)=\frac{1}{B}\sum_{b\le B}\mathcal{A}(\mathcal{D}^{r_b})(x) $ 
#### 3.2 The inflated argmax
- $\operatorname{argmax}^\varepsilon$, a operator on $\mathbb{R}^L$, only applied to $w\in \Delta_{L-1}$ 
##### 3.2.1 Inflated argmax leads to selection stability 
- **Thm 9**(compatibility of inflated argmax): $\forall \varepsilon>0,\, v,w\in \mathbb{R}^L$, $\|v-w\|<\varepsilon$, then $\operatorname{argmax}^\varepsilon(v)\cap\operatorname{argmax}^\varepsilon(w)\ne \varnothing $ 
##### 3.2.2 Additional properties 
- **Prop 10**(Basic properties): Fix $\varepsilon>0$, then 
  - $\forall w\in \mathbb{R}^L$, $\operatorname{argmax}(w)\subset\operatorname{argmax}^\varepsilon(w)$; $\cap_\varepsilon\operatorname{argmax}^\varepsilon(w)=\operatorname{argmax}(w)$ 
  - $\forall w\in \mathbb{R}^L, \varepsilon<\varepsilon'$, $\operatorname{argmax}^\varepsilon (w)\subset \operatorname{argmax}^{\varepsilon'}(w)$ 
  - $\forall w\in \mathbb{R}^L, w_j\le w_k$, $j\in \operatorname{argmax}^\varepsilon(w)\implies k\in\operatorname{argmax}^\varepsilon(w)$ 
  - $w\in \mathbb{R}^L, \sigma\in S_L, v=(w_{\sigma(1)},\cdots, w_{\sigma(L)})$, then $j\in \operatorname{argmax}^\varepsilon(v)\iff\sigma(j)\in \operatorname{argmax}^\varepsilon (w)$ 
- For computation, it's hard to verify $\mathrm{dist}(w,R_j^{\varepsilon})<\varepsilon$, for which we seek an efficient algorithm for computing the inflated argmax set 
- **Prop 11**(Computing): 
  <!-- Fix $w\in \mathbb{R}^L,\varepsilon>0$, and by order $w_{[1]}\ge\cdots\ge w_{[L]} $, define $$\hat{k}=\max\{k\in [L]\colon \left(\sum_{l\le k}(w_{[l]}-w_{[k]}) \right)^2 \}$$ -->
- Next we should verify its optimality, i.e. return as small sets as possible. An example is the *fixed-margin rule*: $$s^\varepsilon_m(w)=\{j\colon w_j>\max_lw_l-\varepsilon/\sqrt{2}\} $$ 
- **Prop 12**(Optimality: **return a singleton set often**): Any selection rule $s\colon \Delta_{L-1}\to 2^{[L]}$ that is $\varepsilon$-compatible, permutation invariant and contains the argmax. Then $\forall w\in \Delta_{L-1}, j\in [L]$, $$s(w)=\{j\}\implies \operatorname{argmax}^\varepsilon(w)=\{j\}$$ 
### 4. Experiments 





### Questions 
- P3 Section 2: check the stochastic approach **random tie breaking rule** (recall that in the paper *ranking problems* stochastic cases are not considered) 
- P8 Section 3.2.2: guess: $\operatorname{argmax}^0=\operatorname{argmax}$?


