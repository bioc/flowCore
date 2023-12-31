## ==========================================================================
## %in% methods are the workhorses to evaluate a filter. Each filter class
## needs to define its own %in% method. Two types of return values are
## allowed: logical vectors for logicalFilterResults and factors for
## multipleFilterResults. In both cases, the length of the return vector
## has to be equal to the number of events (i.e., rows) in the flowFrame.
## In order to provide useful names, factor levels should be chosen
## approriately.
## ==========================================================================






## ==========================================================================
## Figure out useful population names for logical filters from the parameter
## names. First choice are channel descriptors, then channel names.
## ---------------------------------------------------------------------------
popNames <- function(x, table)
{
    mt <- match(parameters(table), parameters(x, names=TRUE))
    desc <- pData(parameters(x))[mt, "desc"]
    names(desc) <- parameters(table)
    noName <- which(is.na(desc) | desc=="")
    desc[noName] <- parameters(x)$name[mt][noName]
    return(desc)
}


#' Filter-specific membership methods
#' 
#' 
#' Membership methods must be defined for every object of type \code{filter}
#' with respect to a \code{flowFrame} object.  The operation is considered to
#' be general and may return a \code{logical}, \code{numeric} or \code{factor}
#' vector that will be handled appropriately. The ability to handle logical
#' matrices as well as vectors is also planned but not yet implemented.
#' 
#' 
#' @name filter-in-methods
#' @aliases %in%-methods %in% %in%,ANY,filterResult-method
#' %in%,ANY,multipleFilterResult-method %in%,ANY,manyFilterResult-method
#' %in%,ANY,filterReference-method %in%,flowFrame,rectangleGate-method
#' %in%,flowFrame,polygonGate-method %in%,flowFrame,ellipsoidGate-method
#' %in%,flowFrame,norm2Filter-method %in%,flowFrame,unionFilter-method
#' %in%,flowFrame,intersectFilter-method %in%,flowFrame,complementFilter-method
#' %in%,flowFrame,subsetFilter-method %in%,flowFrame,filterResult-method
#' %in%,flowFrame,kmeansFilter-method %in%,flowFrame,sampleFilter-method
#' %in%,flowFrame,transformFilter-method %in%,flowFrame,expressionFilter-method
#' %in%,flowFrame,quadGate-method %in%,flowFrame,timeFilter-method
#' %in%,flowFrame,boundaryFilter-method %in%,flowFrame,polytopeGate-method
#' @docType methods
#' 
#' @param x a \code{\linkS4class{flowFrame}}
#' @param table an object of type \code{\linkS4class{filter}} or \code{\linkS4class{filterResult}}
#' or one of their derived classes, representing a gate, filter, or result to check
#' for the membership of x
#' 
#' @return 
#' Vector of type \code{logical}, \code{numeric} or \code{factor} depending on the arguments
#' 
#' @usage 
#' x \%in\% table
#' 
#' @author F.Hahne, B. Ellis
#' @keywords methods
## ==========================================================================
## quadGate -- this is not a logical filter so we return a vector
## of factors indicating a population. Factor levels are later used
## as population names, e.g. when splitting. The evaluation of the
## filter is fully vectorized and should be quite fast.
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="quadGate"),
          definition=function(x,table)
      {
          e <-  exprs(x)[,parameters(table), drop=FALSE]
          desc <- popNames(x,table)
          lev <- c(sprintf("%s+%s+", desc[1], desc[2]),
                   sprintf("%s-%s+", desc[1], desc[2]),
                   sprintf("%s+%s-", desc[1], desc[2]),
                   sprintf("%s-%s-", desc[1], desc[2]))
          factor(lev[as.integer(e[,1] <= table@boundary[1]) +
                     2 * (as.integer(e[,2] <= table@boundary[2]))+1],
                 levels=lev)
      })

## ==========================================================================
## multiRangeGate -- as a logical filter, this returns a logical vector.
## We only allow filtering for the case of min boundary < max boundary for all 
## boundary pairs for the Time channel. The filter evaluation uses 'cut' for efficiency
## reasons.
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",table="multiRangeGate"),
          definition=function(x, table)
          {
            parameters=unlist(parameters(table))
            e <- exprs(x)[,parameters, drop=FALSE]
            tmp <- sapply(seq(along=table@ranges[["min"]]),
                          function(i){
                            if(table@ranges[["min"]][i] < table@ranges[["max"]][i]){
                              !is.na(cut(e[, parameters],
                                         c(table@ranges[["min"]][i],table@ranges[["max"]][i]),
                                         labels=FALSE,
                                         include.lowest = TRUE,
                                         right=FALSE
                              ))
                            }else{
                              rep(FALSE, nrow(e))
                            }})
            if(nrow(e)){
              dim(tmp) <- c(nrow(e), length(table@ranges[["min"]]))
              apply(tmp, 1, any)
            }else{
              return(FALSE)
            }
          })


## ==========================================================================
## rectangleGate -- as a logical filter, this returns a logical vector.
## We only allow filtering for the case of min boundary < max boundary
## for a given parameter. The filter evaluation uses 'cut' for efficiency
## reasons.
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",table="rectangleGate"),
          definition=function(x, table)
      {
          parameters=unlist(parameters(table))
          e <- exprs(x)[,parameters, drop=FALSE]
          tmp <- sapply(seq(along=parameters),
                        function(i){
                            if(table@min[i] > table@max[i]){
                                print(i)
                                e[,i]
                            }else if(table@min[i] == table@max[i]){
                                rep(FALSE, nrow(e))
                            }else{
                                !is.na(cut(e[, i],
                                           c(table@min[i],table@max[i]),
                                           labels=FALSE,
                                           include.lowest = TRUE,
                                           right=FALSE
                                           ))
                            }})
          if(nrow(e)){
              dim(tmp) <- c(nrow(e), length(parameters))
              apply(tmp, 1, all)
          }else{
              return(FALSE)
          }
      })


## ==========================================================================
## polygonGate -- as a logical filter, this returns a logical vector.
## We use a ray casting algorithm to evaluate the filter, and a efficient
## version is implemented in the C function 'inPolygon'. For polygons with
## only a single dimension we fall back to a method using 'cut'.
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame", table="polygonGate"),
          definition=function(x,table)
      {
          parameters=unlist(parameters(table))
          ndim <- length(parameters)

          ## If there is only a single dimension then we have
          ## a degenerate case.
          if(ndim==1)
              !is.na(cut(exprs(x)[,parameters[[1]]],
                         range(table@boundaries[,1]), labels=FALSE,
                         right=FALSE))
          else if(ndim==2) {
            inPolygon(exprs(x)[,parameters,drop=FALSE],table@boundaries)
          } else
          stop("Polygonal gates only support 1 or 2 dimensional gates.\n",
               "Use polytope gates for a n-dimensional represenation.",
               call.=FALSE)
      })


## ==========================================================================
##
## Polytope gate
## Add stuff
##
##
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame", table="polytopeGate"),
          definition=function(x, table)
      {
          parameters=unlist(parameters(table))
          data <- exprs(x)[, parameters, drop=FALSE]
          ## coerce to numeric matrix
          a <- as.numeric(table@a)
          dim(a) <- dim(table@a)
          b <- as.numeric(table@b)
          dim(b) <- dim(table@b)
          inPolytope(data, a, b)
      })



## ==========================================================================
## ellipsoidGate -- as a logical filter, this returns a logical vector.
## We use a covariance matrix / mean representation for ellipsoids here,
## where the eigen vectors of the matrix denote the direction of the
## ellipses principal axes, while the eigen values denote the squared length
## of these axes.
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame", table="ellipsoidGate"),
          definition=function(x,table)
      {   parameters=unlist(parameters(table))

          e <- exprs(x)[,parameters, drop=FALSE]
          W <- t(t(e)-table@mean)
          as.logical(rowSums(W %*% solve(table@cov) * W) <= table@distance ^ 2)

        })



## ==========================================================================
## kmeansFilter -- this is not a logical filter so we return a vector
## of factors indicating a population. Factor levels are later used
## as population names, e.g. when splitting. The kmeans algorithm directly
## gives us the factors, so no need to further evaluate
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="kmeansFilter"),
          definition=function(x,table)
      {
          ## We accomplish the actual filtering via K-means
          param <- parameters(table)[1]
          values <- exprs(x)[, param]
          npop <- length(table@populations)
          km <- kmeans(values, centers=quantile(values, (1:npop)/(npop+1)))
          ## Ensure that the populations are sorted according to their center,
          ## which matches the assumption of the population vector.
          structure(as.integer(order(km$centers)[km$cluster]), class="factor",
                    levels=table@populations)
      })




## ==========================================================================
## timeFilter -- Strictly, this is not a logical filter because
## there might be multiple stretches over time that behave strangly, however
## we treat it as one since there is not real use case for keeping them
## separate. If one wants to restrict the time filtering it can always
## be combined with rectangleGates...
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="timeFilter"),
          definition=function(x,table)
      {
          ## We first bin the data and compute summary statistics
          ## for each bin. These are then used to identify stretches
          ## of unusual data distribution over time. The time parameter
          ## has to be guessed if not explicitely given before.
          ex <- exprs(x)
          if(!length(table@timeParameter))
              time <- findTimeChannel(ex)
          param <- parameters(table)
          bw <- table@bandwidth
          bs <- table@binSize
          if(!length(bs))
              bs <- min(max(1, floor(nrow(x)/100)), 500)
          binned <- prepareSet(x, param, time, bs,
                               locM=median, varM=mad)
          ## Standardize to compute meaningful scale-free scores.
          ## This is done by substracing the mean values of each
          ## bin and divide by the mean bin variance.
          med <- median(binned$smooth[,2], na.rm=TRUE)
          gvars <- mean(binned$variance)
          stand <- abs(binned$smooth[,2]-med)/(gvars*bw)
          outBins <- which(stand > 1)
          bins <- c(-Inf, binned$bins, Inf)
          ## we can treat adjacend regions as one
          ## FIXME: There must be a more elegant way to do that
          if(length(outBins)){
              ld <- length(outBins)
              db <- c(diff(c(0, outBins)),2)
              br <- tr <- NULL
              adj <- FALSE
              for(i in seq_len(ld)){
                  adj <- db[i]==1
                  if(!adj){
                      br <- c(br, outBins[i])
                      if(db[i+1]!=1)
                          tr <- c(tr, outBins[i]+1)
                  }else if(db[i+1]!=1)
                      tr <- c(tr, outBins[i]+1)
              }
              if(db[1]==1)
                  br <- c(outBins[1], br)
              ## Now generate rectangle gates over the identified
              ## regions and use them for the filtering
              ## FIXME: This step is notoriously slow. Is there a
              ## faster way to do that?
              gates <- mapply(function(l,r)
                              rectangleGate(.gate=matrix(c(l,r),ncol=1,
                                              dimnames=list(NULL, time))),
                              bins[pmax(1, br-1)], bins[pmin(length(bins),
                                                             tr+2)])
              # tmp <- filter(x, !gates[[1]])
              # if(length(gates)>1)
              #     for(i in 2:length(gates))
              #         tmp <- filter(x, tmp & !gates[[i]])
              # return(as.logical(tmp@subSet) )
              
              ##we don't do the complementary(!) and intersectFilter(&) filter anymore 
              ## since they creates huge memory overhead by appending the filter results recursively
              tmp <- filter(x, gates[[1]])@subSet
              if(length(gates)>1)
                for(i in 2:length(gates))
                  tmp <- tmp | filter(x, gates[[i]])@subSet
              return(!tmp)
          }else
              return(rep(TRUE, nrow(x)))
        })

## Run over a cytoFrame, bin the values according to the time domain
## and compute a location measure locM as well as variances varM for each bin.
## The result of this function will be the input to the plotting functions
## and the basis for the quality score.
prepareSet <- function(x, parm, time, binSize, locM=median, varM=mad)
{
    exp <- exprs(x)
    ## remove the margin events first
    r <- range(x)[, parm, drop = FALSE]
    sel <- exp[,parm]>r["min",] & exp[,parm]<r["max",]
    xx <- exp[sel, time]
    ord <- order(xx)
    xx <- xx[ord]
    yy <- exp[sel, parm][ord]
    lenx <- length(xx)
    nrBins <- floor(lenx/binSize)
    ## how many events per time tick
    nr <- min(length(unique(xx)), max(51, nrBins))
    timeRange <- seq(min(xx), max(xx), len=nr)
    hh <- hist(xx, timeRange, plot = FALSE)
    freq <- hh$counts
    expEv <- length(xx)/(nr-1)
    ## time parameter is already binned or very sparse events
    ux <- unique(xx)
    if(length(ux) < nrBins){
        tmpy <- split(yy, xx)
        yy <- sapply(tmpy, locM, na.rm=TRUE)
        xx <- unique(xx)
        binSize <- 1
    }else{
        ## bin values in nrBins bins
        if(lenx > binSize){
            cf <- c(rep(1:nrBins, each=binSize),
                    rep(nrBins+1, lenx-nrBins*binSize))
            stopifnot(length(cf) == lenx)
            tmpx <- split(xx,cf)
            tmpy <- split(yy,cf)
            yy <- sapply(tmpy, locM, na.rm=TRUE)
            xx <- sapply(tmpx, mean, na.rm=TRUE)
        }else{
            ## very little events
            warning("Low number of events", call.=FALSE)
            tmpy <- split(yy,xx)
            yy <- sapply(tmpy, locM, na.rm=TRUE)
            xx <- unique(xx)
            binSize <- 1
        }
    }
    var <- sapply(tmpy, varM, na.rm=TRUE)
    ## avoid 0 variance estimates created by mad
    zv <- which(var==0)
    if(length(zv))
       var[zv] <- mean(sapply(tmpy, sd, na.rm=TRUE), na.rm=TRUE)
    return(list(smooth=cbind(xx,yy), variance=var, binSize=binSize,
                frequencies=cbind(timeRange[-1], freq),
                expFrequency=expEv, bins=unique(xx)))
}

## Guess which channel captures time in a flowFrame
findTimeChannel <- function(xx, strict=FALSE)
{
    time <- grep("^Time$", colnames(xx), value=TRUE,
                 ignore.case=TRUE)[1]
    if(is.na(time)){
        if(is(xx, "flowSet")||is(xx, "ncdfFlowList"))
            xx <- exprs(xx[[1]])
		else if (is(xx, "flowFrame"))
			xx <- exprs(xx)
        cont <- apply(xx, 2, function(y) all(sign(diff(y)) >= 0))
        time <- names(which(cont))
    }
    if(!length(time) && strict)
        stop("Unable to identify time domain recording for this data.\n",
             "Please define manually.", call.=FALSE)
    if(length(time)>1)
        time <- character(0)
    return(time)
}



## ==========================================================================
## complementFilter -- Returns TRUE when the input filter is FALSE.
## --------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="complementFilter"),
          definition=function(x,table)
      {
          r <-  filter(x,table@filters[[1]])
          z <- !as(r,"logical")
          attr(z,'filterDetails') <- filterDetails(r)
          z
      })



## ==========================================================================
## unionFilter -- returns TRUE if ANY of the argument filters return true.
## --------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame", table="unionFilter"),
          function(x,table)
      {
          fr <- sapply(table@filters, filter, x=x)
	  ## If we have a multipleFilterResult and a logical
	  ## filter result we have to dissect the two
	  mfr <- sapply(fr, is, "multipleFilterResult")
	  if(sum(mfr)>1)
	     stop("'unionFilters' are not defined when several ",
	          "filter objects return 'multipleFilterResults.")
 	  if(any(mfr))
	  {
	     res <- fr[mfr][[1]]@subSet
	     resL <- sapply(fr[!mfr], slot, "subSet")
 	     resM <- !is.na(res)
             if(any(resL & resM))
	        stop("unionFilters are not defined for overlapping",
		     " populations.")
	     l <- levels(res)
	     nl <- make.unique(c(sapply(fr[!mfr],
                     identifier), l))[1:sum(!mfr)]
             levels(res) <- c(l, nl)
	     for(i in seq_along(nl))
	        res[resL[,i]] <- nl[i]
          }
	  else
	  {
             res <- apply(matrix(sapply(fr, as, "logical"),
                          ncol=length(table@filters)), 1, any)
	  }
          details <- list()
          for(i in fr) {
              fd <- filterDetails(i)
              details[names(fd)] <- fd
          }
          attr(res,'filterDetails') <- details
          res
      })



## ==========================================================================
## intersectFilter -- only returns TRUE if ALL the member filters are TRUE.
## --------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="intersectFilter"),
          definition=function(x,table)
          {
              fr <- sapply(table@filters, filter, x=x)
	      ## If we have a multipleFilterResult and a logical
	      ## filter result we have to dissect the two
	      mfr <- sapply(fr, is, "multipleFilterResult")
	      if(sum(mfr)>1)
	         stop("'intersectFilters' are not defined when several ",
		     "filter objects return 'multipleFilterResults.")
	      if(any(mfr))
	      {
		 res <- fr[mfr][[1]]@subSet
	         res[!as(fr[!mfr][[1]], "logical")] <- NA
	      }
              else
	      {
                 res <- apply(matrix(sapply(fr, as, "logical"),
                              ncol=length(table@filters)), 1, all
                             )
	      }
              details <- list()
              for(i in fr)
              {
                  fd <- filterDetails(i)
                  details[names(fd)] <- fd
              }
              attr(res,'filterDetails') <- details
              res
          }
         )


## ==========================================================================
## subsetFilter -- Returns TRUE for elements that are true on
## the LHS and the RHS, however the LHS filter is only executed
## against the subset returned by the RHS filtering
## operation. This is particularly important for unsupervised filters like
## norm2Filter. The result is still relative to the ENTIRE flowFrame however.
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="subsetFilter"),
          definition=function(x, table)
      {
          y <- filter(x,table@filters[[2]])
          z <- if(is(y, "logicalFilterResult"))
          {
              w <- as(y,"logical")
              n <- which(w)
              r <- filter(x[n,], table@filters[[1]])
              filterDetails(y, identifier(table@filters[[1]])) <-
                  summarizeFilter(r, table@filters[[1]])
              attr(w,'subsetCount') <- sum(w)
              if(is(r, "logicalFilterResult"))
              {
                  w[n[!as(r,"logical")]] <- FALSE
              }
              else
              {
                  wn <- rep(NA, length(w))
                  wn[w][!is.na(r@subSet)] <- r@subSet[!is.na(r@subSet)]
                  ll <- unique(wn)
                  w <- factor(wn,levels=ll[!is.na(ll)])
              }
              w
          } else {
              res <- rep(NA,nrow(x))
              ll <- paste(identifier(table@filters[[1]]),"in",names(y))
              count <- rep(0,length(y))
              for(i in seq(along=y)) {
                  w <- as(y[[i]],"logical")
                  count[i] <- sum(w)
                  n <- which(w)
                  r <- filter(x[n,],table@filters[[1]])
                  filterDetails(y,ll[i]) <-
                      summarizeFilter(r, table@filters[[1]])
                  w[n[!as(r,"logical")]] <- FALSE
                  res[w] <- i
              }
              w <- structure(as.integer(res),levels=ll)
              attr(w,'subsetCount') <- count
          }
          ## We need to track our filterDetails to a higher level
          ## for summarizeFilter.
          attr(z,'filterDetails') <- filterDetails(y)
          z
      })

## ==========================================================================
## sampleFilter -- We randomly subsample events here.
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="sampleFilter"),
          definition=function(x, table)
      {
          n <- if(table@size > nrow(x)) nrow(x) else table@size
          l <- rep(FALSE,nrow(x))
          l[sample(length(l), n, replace=FALSE)] <- TRUE
          l
      })



## ==========================================================================
## boundaryFilter -- We remove boundary events
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="boundaryFilter"),
          definition=function(x, table)
      {
          ranges <- range(x)
          exp <- exprs(x)
          if(nrow(exp)==0)
              return(as.logical(NULL))
          res <- as.matrix(sapply(parameters(table), function(z){
              low <- exp[,z]>ranges[1,z]+table@tolerance[z]
              high <- exp[,z]<ranges[2,z]-table@tolerance[z]
              switch(table@side[z],
                     both=low & high,
                     upper=high,
                     lower=low)
          }))
          res[is.na(res)] <- TRUE
          return(apply(res, 1, all))
      })



## ==========================================================================
## expressionFilter -- The expression has to evaluate to a logical vector
## or a factor
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="expressionFilter"),
          definition=function(x, table)
      {
          data <- flowFrame2env(x)
	  data <- as.list(data)
          if(length(table@args)==1){
              res <- eval(table@expr, data, enclos=table@args[[1]])
          }else{
              res <- eval(table@expr, data, enclos=baseenv())
          }
      })

## function to convert a flowframe into an environment, so we
## can subsequently eval() things in it.
flowFrame2env <- function(ff)
{
    ffdata <- exprs(ff)
    e <- new.env()
    cn <- colnames(ff)
    for (i in seq_along(cn))
    {
        e[[ cn[i] ]] <- ffdata[, i]
    }
    e
}

## ==========================================================================
## transformFilter -- We transform the data prior to gating
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="transformFilter"),
          definition=function(x, table)
      {
          (table@transforms %on% x) %in% table@filter
      })



## ==========================================================================
## filterReference -- We grab the filter from the filter reference and
## evaluate on that
## ---------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="ANY",table="filterReference"),
          definition=function(x, table)
                     {
                      #x %in% as(table@env[[table@name]], "concreteFilter")
                      filter=as(table, "concreteFilter")
                      parameters=slot(filter,"parameters")
                      len=length(parameters)
                      charParam=list()
                      while(len>0)
                      {
                          if(class(parameters[[len]])!="unitytransform")
                          {   ## process all transformed parameters
                              charParam[[len]]=sprintf("_NEWCOL%03d_",len)
                              newCol=eval(parameters[[len]])(exprs(x))
                              colnames(newCol)=sprintf("_NEWCOL%03d_",len)
                              data <- cbind(data, newCol)
                          }
                          else
                          {
                              charParam[[len]]=slot(parameters[[len]],"parameters")

                          }
                          len=len-1
                      }
                      slot(filter,"parameters")=new("parameters",.Data=charParam)
                      x %in% filter
                      }
         )

## ==========================================================================
## filterResult -- Lets us filter by filterResults, rather than filters,
## but only as long as we have a logicalFilterResult or randomFilterResult
## --------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="flowFrame",
                              table="filterResult"),
          definition=function(x, table) as(table, "logical"))



## ==========================================================================
## manyFilterResult -- We only know how to filter on manyFilterResults if
## one and only one subpopulation is specified
## --------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="ANY",
                              table="manyFilterResult"),
          definition=function(x, table)
          stop("manyFilterResult: You must specify a subpopulation."))



## ==========================================================================
## multipleFilterResult -- We only know how to filter on manyFilterResults if
## one and only one subpopulation is specified
## --------------------------------------------------------------------------
#' @export
setMethod("%in%",
          signature=signature(x="ANY",
                              table="multipleFilterResult"),
          definition=function(x, table)
          stop("multipleFilterResult: You must specify a subpopulation."))
