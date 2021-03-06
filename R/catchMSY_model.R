#' Age-structured Catch-MSY model
#' @description An age-structured assessment model paramterized using MSY and FMSY  
#' as the leading parameters, and the instantaneous natural mortality  rate. This function generates biomass estimates, estimates of fishing mortality rates, and stock depletion.  It also returns statistical criterion depending on the available data, and non-statistical criterion based on satisfying user specified constraints.
#' 
#' @details
#' The age-structured model is conditioned on the historical catch data 
#' (in weight).  The catch equation assumes that both
#' fishing mortality and natural mortality are occuring simultaneously, and the
#' instantaneous fishing mortality rate is found by solving the Baranov catch 
#' equation \eqn{C =  F/Z*(1-exp(-Z))*B}, for \code{F}. 
#'
#' @param sID Stock ID object
#' Set to TRUE when including the prior on sel1 (sel50) 
#' @param nlSearch Boolean flag to turn off non-statistical criterion for 
#' non-linear search. Set to TRUE when using non-linear search routines.
#' @param selex Boolean flag to turn off search across sel1 (sel50) parameter. 
#' @export
catchMSYModel <- function(sID,nlSearch=FALSE,selex=FALSE)
{
	with(sID,{

		# calcAgeSchedules
		nage <- max(age)
		la <- linf*(1.0-exp(-vbk*(age-to)))
		la.sd <- la.cv*la
		wa <- a*la^b
		ma <- plogis(age,ah,gh)
		fa <- wa*ma #fecundity is assumed to be proportional to mature body weight.
		if(smodel=="logistic") va <- 1.0/(1.0+(exp(-log(19)*((age-sel1)/(sel2-sel1)))))
		if(smodel=="dome"){
			va <- rep(NA, length(age))
			for(a in 1:length(age)){
				if(a <= sel2) va[a] <- 1.0/(1.0+(exp(-log(19)*((age[a]-sel1)/(sel2-sel1)))))
				if(a > sel2) va[a] <- exp(-(age[a]-sel2)^2/(2*dome_sd^2))
			}
		}
		#todo  add option for survey selectivy (CIE review request.)
		lx <- exp(-m*(age-min(age)))
		lx[max(age)] <- lx[max(age)]/(1.0-exp(-m))
		phie <- sum(lx*fa)

		# Ford-Brody Growth parameter transformation
		rho   <- exp(-vbk)
		alpha <- winf*(1-rho)
		wk    <- wa[nage-1]
		s     <- exp(-m)
		wbar  <- -(s*alpha+wk*(1-s))/(-1+s*rho)
		# print(wbar)

		# calcBoSteepness
		lz	<- vector("numeric",length=length(age))
		za  <- m + fmsy*va
		sa  <- exp(-za)
		oa  <- (1-sa)
		qa  <- va*oa/za
		t2  <- wa*va^2/za
		t3  <- exp(-za)-oa/za
		lz[1]    <- 1.0
		dlz.df	 <- 0.0
		dphie.df <- 0.0
		dphiq.df <- t2[1]*t3[1]
		for(i in age)
		{
			if(i > min(age))
			{
				lz[i]  <- lz[i-1] * sa[i-1]
				dlz.df <- dlz.df  * sa[i-1] - lz[i-1]*va[i-1]*sa[i-1]
				if(i==max(age))
				{
					lz[i]  <- lz[i]/oa[i]
					dlz.df <- dlz.df/sa[i] - lz[i-1]*sa[i-1]*va[i]*sa[i]/oa[i]^2 
				}
			}
			dphie.df <- dphie.df + fa[i]*dlz.df
			dphiq.df <- dphiq.df + wa[i]*qa[i]*dlz.df + lz[i]*t2[i]*t3[i]
		}
		phif  <- sum(lz*fa)
		phiq  <- sum(lz*qa*wa)
		reck  <- phie/phif - (fmsy*phiq*phie/phif^2*dphie.df) / (phiq+fmsy*dphiq.df)
		steep <- reck/(4+reck)

		re 	   <- msy / (fmsy*phiq)
		ro     <- re*(reck-1.0)/(reck-phie/phif)
		bo     <- ro * phie
		so     <- reck/phie
		beta   <- (reck-1.0)/bo
		spr_msy    <- phif/phie
		dre.df <- ro/(reck-1.0)*phie/phif^2*dphie.df

		# runAgeStructuredModel
		names(data) <- tolower(names(data))
		year <- data$year
		chat <- data$catch
		# cpue <- data$index
		nyr  <- length(year)
		

		N    <- C <- matrix(nrow=length(year),ncol=length(age))
		N[1,]<- ro*lx
		ft   <- vector("numeric",length=length(year))
		spr_t <- vector("numeric",length=length(year))
		bpls <- vector("numeric",length=length(year))
		apo  <- age[-min(age)]
		amo  <- age[-max(age)]
		
		for (i in 1:nyr) 
		{
			ft[i]	   <- getFt(chat[i],m,va,wa,N[i,])

			lt <- vector("numeric", length=length(age))
			lt[1] <- 1.0
			zat  <- m + ft[i]*va
			sat  <- exp(-zat)
			for(aa in age){
				if(aa > min(age)) lt[aa] <- lt[aa-1] * sat[aa-1]
				if(aa==max(age)) lt[aa] <- lt[aa]/(1-sat[aa])
			}
			spr_t[i] <- sum(lt*fa)/phie
			rm(lt)

			st         <- exp(-m-ft[i]*va)
			ssb        <- sum(N[i,]*fa)
			# spls       <- exp(-m-ft[i]*va[nage])
			# bpls[i]    <- spls*(alpha*N[i,nage]+rho*)
			if(i < nyr)
			{
				N[i+1,1]   <- so*ssb/(1+beta*ssb)*exp(rnorm(1,0,sigma_r) - (sigma_r^2)/2)
				N[i+1,apo] <- N[i,amo] * st[amo]
				N[i+1,nage]<- N[i+1,nage]+N[i,nage] * st[nage]
			}
			C[i,] = N[i,] * (1 - st) * (ft[i] * va) / (m + ft[i] * va)
		}
		
		ct  <- rowSums(C)
		bt  <- as.vector(N %*% (va*wa))
		sbt <- as.vector(N %*% fa)
		dt  <- sbt/bo
		depletion <- sbt[nyr]/bo

		
		#----------------------------------------------#
		# NON-STATISTICAL CRITERION                    #
		#----------------------------------------------#
		code <- 0
		if(!nlSearch){
			# check for extinction
			if( any(is.na(sbt)) ) { code <- 1 }

			# check for infinite biomass
			if( any(is.infinite(sbt)) )	  { code <- 2 }
			
			# check for lower bound tolerance
			if(!is.na(depletion) && depletion <= lb.depletion) { code <- 3 }

			# check for upper bound depletion tolerance
			if(!is.na(depletion) && depletion >= ub.depletion) { code <- 4 }

			# check bounds for ft.
			if( max(ft,na.rm=TRUE) > 5.0 
			   || any(is.infinite(ft)) 
			   || min(ft,na.rm=TRUE) < 0 
			   || all(is.na(ft))) { code <- 5}

			# check estimates of steepness
			if(is.na(reck)==FALSE) if( reck <= 1.0 ) { code <- 6 }	
		}

		#----------------------------------------------#
		# STATISTICAL CRITERION                        #
		#----------------------------------------------#
		nll <- rep(0,length=4) ## fit to index, biomass, length comp, mean length
		Q   <- 	Qp <- LF <- ML <- biomass_resid <- index_resid <- lc_resid <- ml_resid <- NULL
		# Must first pass the non-statistical criterion.
		if( code == 0 ){

			bw <- 1 #bin width = 1 cm
			A  <- max(age)
			if(all(grepl("lc.", colnames(data))==FALSE)){
				l1 <- floor(la[1]-3*la.sd[1])
				l2 <- ceiling(la[A]+3*la.sd[A])
				bin  <- seq(1,l2+bw,by=bw)
			}
			if(any(grepl("lc.", colnames(data)))){
				bin <- as.numeric((sapply(1:length(colnames(data)[which(grepl("lc.", colnames(data)))]), function(x) strsplit(colnames(data[which(grepl("lc.", colnames(data)))]), ".", fixed=TRUE)[[x]][2])))
			}
			bw <- diff(bin[1:2])
			ALK<- sapply(bin+(bw/2),pnorm,mean=la,sd=la.sd)-sapply(bin-(bw/2),pnorm,mean=la,sd=la.sd)
			
			falk <- function(ii)
			{
				iiQ  <- (N[ii,]*va) %*% ALK	
				return(iiQ)	
			}
			ii <- which(!is.na(data$catch))
			Q  <- sapply(ii,falk) ## vulnerable abundance at length in each year
			ML <- sapply(ii, function(x) sum(Q[,x]*bin)/sum(Q[,x]))
			Qp <- sapply(ii, function(x) Q[,x]/sum(Q[,x]))
			LF <- sapply(ii, function(x) rmultinom(n=1, size=1000, prob=Qp[,x]))
				rownames(Q) <- rownames(Qp) <- rownames(LF) <- paste0("lc.", bin)


			# Relative abundance (trend info)
			# If code==0, and abundance data exists, compute nll
			if(any(grepl("index", colnames(data)))){
				if( any(!is.na(data$index)) ) {
					 ii <- which(!is.na(data$index))
					.it <- data$index[ii]
					.se <- data$index.lse[ii]
					if(length(.it)>1){
						.zt    <- log(.it) - log(bt[ii])
						.zbar  <- mean(.zt)
						index_resid <- .zt - .zbar
						nll[1] <- -1.0*sum(dnorm(.zt,.zbar,.se,log=TRUE))
					}
					else{
						cat("There is insufficient data to fit to trends.")
					}
				}
			}

			# Absolute biomass index.
			if(any(grepl("biomass", colnames(data)))){
				if( any(!is.na(data$biomass)) ) {
					ii     <- which(!is.na(data$biomass))
					.btobs    <- log(data$biomass[ii])
					.bt    <- log(bt[ii])
					.se    <- data$biomass.lse[ii]
					biomass_resid <- .btobs - .bt
					nll[2] <- -1.0*sum(dnorm(.btobs,.bt,.se,log=TRUE))
				}
			}

			#
			# Size comp likelihood here
			if(any(grepl("lc.", colnames(data)))){
				lc <- data[,grep("lc.", colnames(data))]
				.sd <- data[,grepl("lencomp_sd", colnames(data))]
				il <- which(is.na(rowSums(lc))==FALSE)
				tlc <- lc + 1e-20
				.qobs <- tlc/rowSums(tlc)
				.qexp <- t(Qp)
				Aprime <- ncol(lc)

				## richards and schnute -- L.8 & L.11
				## multivariate logistic
				lc_resid <- sapply(il, function(x) log(.qobs[x,]) - log(.qexp[x,]) - (1/Aprime)*sum(log(.qobs[x,]) - log(.qexp[x,])))
				tresid <- t(lc_resid)
				loglike <- sapply(il, function(x) (1/2)*log(Aprime) - (Aprime-1)*((1/2)*log(2*pi) + log(.sd[x])) - (1/(2*.sd[x]^2))*sum(unlist(tresid[x,])^2))
				nll[3] <- -sum(loglike)

				
				## dirichlet-multinomial
				## not ideal due to optimization within SIR algorithm
				## effective sample size estimated to be very low due to random draws from priors of FMSY and MSY far from the truth
				# dmult <- function(log_theta, n, obs, pred){
				# 	theta <- exp(log_theta)
				# 	# like <- (gamma(n+1)/prod(gamma(n*obs + 1)))*(gamma(theta*n)/gamma(n+theta*n))*prod((gamma(n*obs + theta*n*pred)/gamma(theta*n*pred)))
				# 	loglike <- lgamma(n+1) - sum(lgamma(n*obs+1)) + lgamma(theta*n) - lgamma(n+theta*n) + sum(lgamma(n*obs+theta*n*pred) - lgamma(n*theta*pred))
				# 	nll <- -loglike
				# 	return(nll)
				# }
				# nll_lc <- sapply(il, function(x) optimize(dmult, interval=c(log(1e-20),log(10)), n=sum(.qobs[x,]), obs=.qobs[x,]/sum(.qobs[x,]), pred=.qexp[x,])$objective)
				# nll <- sum(nll_lc)



				## multinomial - can brute force it to work by setting ESS around 10
				# ll_lc <- sapply(il, function(x) dmultinom(as.numeric(.qobs[x,]/sum(.qobs[x,]))*1, prob=.qexp[x,], log=TRUE))
				# nll[3] <- -sum(ll_lc)
			}

			# Mean length likelihood
			if(any(grepl("avgSize", colnames(data)))){
				if( any(!is.na(data$avgSize)) ) {
					ii     <- which(!is.na(data$avgSize))
					.mlobs    <- log(data$avgSize[ii])
					.mlexp    <- log(ML[ii])
					ml_resid <- .mlobs - .mlexp
					.se    <- data$avgSize.lse[ii]
					nll[4] <- -1.0*sum(dnorm(.mlobs,.mlexp,.se,log=TRUE))
				}
			}




		}

		# -------------------------------------------- #
		# PRIORS                                       #
		# -------------------------------------------- #
		# prior for parameters
		if(selex==FALSE){
			.x    <- c(m,fmsy,msy)
			vec <- 1:3
		}
		if(selex==TRUE){
			.x <- c(m,fmsy,msy,sel1)
			vec <- 1:4
		}
		pvec <- rep(0,length(vec))
		for(.i in vec)
		{
			.fn <- paste0("d",dfPriorInfo$dist[.i])
			.p1 <- dfPriorInfo$par1[.i]
			.p2 <- dfPriorInfo$par2[.i]
			.p3 <- dfPriorInfo$log[.i]
			pvec[.i] <- -1.0*do.call(.fn,list(.x[.i],.p1,.p2,.p3))
		}
		
		# cat(m,"\t",fmsy,"\t",msy,"\t",sum(nll)+sum(pvec),"\n")

		out <- list(code=code,
		            bo = bo, h=steep,
		            wa = wa, va=va, 
		            reck = reck,spr_msy = spr_msy,
		            spr_t = spr_t, 
		            nll=sum(nll,na.rm=TRUE),
		            prior=sum(pvec,na.rm=TRUE),
		            dt=dt,bt=bt,sbt=sbt,ft=ft,Q=Q,Qp=Qp,ML=ML,LF=LF,
		            biomass_resid=biomass_resid, index_resid=index_resid, lc_resid=lc_resid, ml_resid=ml_resid)
		return(out)
	})
}
