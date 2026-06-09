## Note of *Bagging Provides Assumption-free Satbility* 

### Framework

### Work 
- Write proof sketches 


### Direction of work 
#### proof sketches
- **Thm 8**: Stability of **derandomized bagging** $\widetilde{\mathcal{A}}_{\infty}$. Note the use of *Popovicius Ineq*, and that $q\ge 0$ (it may mean the sample data complete to be selected)
- **Thm 9**: Stability of Generic bagging $\widetilde{\mathcal{A}}_{B}$. *Hoeffding's Ineq* is not easy. 
- **Thm 10**: This theorem seeks to name a **counterexample**. The HyperGeometry setting shows its magic, and only the last part of the proof is important. 
- **Thm 12**: 
- **Thm 13**: Note that like Algorithm 3, $$\hat{f}_{\infty,I}(x)=\mathbb{E}_r[\mathrm{Clip}_{I(\mathcal{D})}\hat{f}^{(b)}(x)]. $$ Here we can regard `Clip` as part of the Algorithm, whose output is bounded by $[u,l]$. That's why in the first step of the proof, we could bound the first term using the generalization of **Thm 8**. 
- **Thm 14**: About worst-case stability. For $\varepsilon=p$, it's good yet once $\varepsilon<p$ it goes wrong. 
- **Cor15**: 
- **Cor16**: Use i.i.d. to convert it into average form, and then use Fubini. 


### Questions
- P13: See the equations starting with $R$, what exactly is the *empirical range*? Why do we use $\sup_{r:\mathcal{Q}_n(\{r\} ) >0}$? Isn't it supposed to be the same across all $r$?      ✅