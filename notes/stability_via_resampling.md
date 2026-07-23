## Note of *Stability via Resampling: Statistical Problems Beyond the Real Line* 

### Information 
Find the paper [here](https://github.com/EmersonWon/Stability---Summer-Research/tree/main/Paper). 
- **Author**: Jake A. Soloff, Rina Foygel Barber, and Rebecca Willet 
- **Keyword**: 

### 1. Introduction 
- This paper follows the last one, namely *Bagging Provides ...* 
#### 1.1 Problem Settings 
- **Problem 1**: In supervised learning, there's many scenarios that the last paper's result about $\mathbb{R}$-value returns cannot covers, e.g. a function, or a vector of weights as the returns 
- **Problem 2**: In Bayesian inference, we are intersted in th e posterior distribution of the parameter $\theta$, which is a vector of weights in discrete situations. Alternatively, if $\theta$ takes values in a continuous space, say $\mathbb{R}^d$, the result should be a distribution over $\mathbb{R}^d$ 
- **Problem 3**: The use of *synthetic control method* (SCM) in causal inference, whose output is a weighted vector 
- Other problems: Constrained Lasso/Ridge (on $\ell_q$-ball), Nonparametric regression (on Sobolev ball of funtions) 


#### 1.2 "Our" Contributions 
- Goal: to establish quantitative guarantees on the stability of those whose output might not be real-valued 
- Condition: Outputs are in bounded subset of a separable Hilbert or Banach space 

### 2. Framework: algorithmic stability in a metric space 
> I hereby will skip the contents that are included by the last paper. 

- $\mathcal{A}\colon \bigcup_n \mathcal{Z}^n\times [0,1]\to (\mathcal{W},d) $ 
- We combine these $\mathcal{Z}^i$ to allow dropping samples 

#### 2.1 Defining stabiltiy 
- **Definition 1**: Mean-square stability $\beta^2$: for all data sets from $\mathcal{Z}^n$, $$\frac{1}{n}\sum_{i=1}^n\mathbb{E}_\xi[d^2(\hat{w},\hat{w}^{\setminus i})]\le \beta^2. $$ This captures the average perturbation 
- **Definition 2**: Tail stability $(\varepsilon,\delta)$ w.r.t. $d$: for all data sets, $$\frac{1}{n}\sum_{i=1}^n\mathbb{P}_\xi\left(d(\hat{w},\hat{w}^{\setminus i})\ge \varepsilon\right)\le \delta $$ 
- **Proposition 3**: Mean-square $\beta^2\Rightarrow $ tail stability $(\varepsilon, \delta)$ where $\delta\varepsilon^2\ge \beta^2 $; Tail stability $(\varepsilon,\delta)\Rightarrow $ mean-square stability $\beta^2\coloneqq \varepsilon^2+\delta\sup_{w,w'\in \mathcal{W}}d^2(w,w') $. This means that these 2 stability can convert to each other 

#### 2.2 Related notion of stability 


### Questions
- P15, proof of Thm 6: How could we directly exchange the order of inner product and expectation? 
- How does *separable* work? 