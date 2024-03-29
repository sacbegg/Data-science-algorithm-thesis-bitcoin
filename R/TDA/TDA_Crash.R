# Takes one dimensional time series, performs delay embedding
one_d <-function(data, embed_dim = 4)
{
  #if (embed_dim == 0) {
  #embed_dim <- estimateEmbeddingDim(data, do.plot = FALSE)
  #}
  edata <- embed(data, embed_dim)
  return(edata)
}

#Takes time series and scales, either using max values or taking log
pre_process <- function(data, scaling_method)
{
  tmp <- data
  #if (scaling_method == "log") {
    #tmp <- log(tmp)
  #}
  
  if (scaling_method == "max") {
    for (i in 1: ncol(tmp)) {
      tmp[,i] <- tmp[,i]/max(abs(tmp[,i]))
    }
  }
  
  #if (scaling_method == "return") { 
  
  # for(i in 1:ncol(tmp)) {
  #replace each column in the data set with the log return
  #replace corresponding column in dat with new log return value
  #  tmp[,i] <- Delt(tmp[,i])
  #}
  #Since first vale will always be N/A, remove it
  #tmp <- tmp[-1,]
  #}
  return(tmp)
}

log_r <- function(tmp)
{
  for(i in 1:ncol(tmp)) {
    #replace each column in the data set with the log return
    #replace corresponding column in dat with new log return value
    tmp[,i] <- Delt(tmp[,i])
  }
  #Since first vale will always be N/A, remove it
  tmp <- tmp[-1,]
  return(tmp)
}

#Finds upper bound of diameter of the data 
#to use for max_scale
find_diam <- function(time) 
{
  dim <- ncol(time)
  diam_list = vector(length = dim)
  for (i in 1:dim) {
    high <- max(time[,i])
    low <- min(time[,i])
    diam_list[i] <- (high-low)
  }
  diam <- norm(diam_list, type = "2")
  return(diam)
}

#Takes time series and finds persistence diagrams
nd_diag <- function(time, max_scale = 0.1, K_max = 10, window = 10) 
{
  tmp <- time
  
  #TDA
  maxdimension =1
  Diags1.rips.ls = list()
  total <- dim(tmp)[1]
  step <- 1
  spot <- seq(from=1, to=(total-window+1), by=step)
  
  #Persistence diagrams
  cat("Computing persistence diagrams...")
  pb <- txtProgressBar(min = 0, max = length(spot), style = 3)
  for(i in 1:length(spot)){
    Diags1.rips.ls[[i]] = 
      ripsDiag(tmp[spot[i]:(spot[i]+window-1), ], maxdimension=1, max_scale, library = "GUDHI")
    
    # update progress bar
    setTxtProgressBar(pb,i)
  }
  #plot(Diags1.rips.ls[[i]]$diagram)
  return(Diags1.rips.ls)
}

#Takes the diagrams from nd_diag and calculates the norm
nd_norm <- function(diag, max_scale, K_max = 10, scaling_method = "log"){
  step <- 1
  spot <- seq(from =1, to = length(diag), by = step)
  
  ###### PR (2018-12-16): This line is WRONG and should be removed. See below!!!
  #tseq <- seq(0, max_scale, length =length(spot)) 
  
  Lands1.ls = list() # collects landscapes (in 2D) at particular date i per k 
  AUC_Land.m = matrix(0,length(spot),K_max) #collects values of lambda_k at particular date i per k 
  AUC_Land.v = vector(length=length(spot)) #collects values of L^1 at particular date
  #Compute L^1
  cat("Computing the L1 norm of persistence landscapes...")
  pb <- txtProgressBar(min = 0, max = length(spot), style = 3)
  for (i in 1:length(spot)){
    diagram <- diag[[i]]$diagram
    
    #print(diagram)
    # Look at persistence diagrams on a logarithmic scale
    if(scaling_method=="log") {
      # Only take logarithm of nonzero entries
      for(j in 1:nrow(diagram)) {
        if(diagram[j,1]==1) {
          diagram[j,2] = log(diagram[j,2])
          diagram[j,3] = log(diagram[j,3])
        }
      }
    }
    
    minim=Inf
    maxim=-Inf
    for(j in 1:nrow(diagram)) {
      if(diagram[j,1]==1) {
        minim = min(minim,diagram[j,2])
        maxim = max(maxim,diagram[j,3])
      }
    }
    #print(minim)
    #print(maxim)
    
    if(minim==Inf)  # There is no 1-dimensional homology feature in this window
    {
      AUC_Land.v[i]=0
    }
    else 
    {
      tseq <- seq(minim, maxim, length=500)
      AUC_Land.v[i]=0
      for (KK in 1:K_max){
        Lands1.ls[[i]]=landscape(diagram, dimension=1, KK, tseq)
        #print(head(Lands1.ls[[i]]))
        AUC_Land.m[i,KK]=  pk.calc.auc.all(Lands1.ls[[i]],tseq, interval=c(minim,maxim))
        AUC_Land.v[i]= AUC_Land.v[i]+AUC_Land.m[i,KK]
      }
    }
    # update progress bar
    setTxtProgressBar(pb,i)
  }
  return(AUC_Land.v)
}

#End line method - takes multi-D time series, processes, 
#and finds the norm
#Default max_scale of 0 leads to find_diam being called
analyze_nd <- function(time, scaling_method = "log", returns = FALSE, 
                       max_scale = 0, K_max = 10, window = 50) {
  dates <- index(time)
  if (returns) {
    #Taking log-returns of the log of the data can lead to errors, 
    #so if returns are desired, we deactivate the log scaling
    if (scaling_method =="log") {
      scaling_method <- "none"
    }
    time <- log_r(time)
  }
  
  data <- pre_process(time, scaling_method)
  if(max_scale == 0) {
    max_scale <- find_diam(data)
  }
  diag <- nd_diag(data, max_scale, K_max, window)
  norm <- nd_norm(diag, max_scale, K_max, scaling_method)
  new_dates <- tail(dates, length(norm))
  norm.xts <- xts(norm, order.by = new_dates)
  
  
  return(norm.xts)
}

#End line method - takes one-D time series 
#finds delay embedding, calls analyze_nd
analyze_1d <- function(time, dim = 4, scaling_method = "log", max_scale = 0, K_max = 10, window = 50, returns = FALSE) {
  if (returns) {
    #Taking log-returns of the log of the data can lead to errors, 
    #so if returns are desired, we deactivate the log scaling
    if (scaling_method == "log") {
      scaling_method <- "none"
    }
    
    time <- log_r(time)
  }
  dates <- index(time)
  
  delay_data <- one_d(time, dim)
  delay_data.xts <- xts(delay_data, order.by = tail(dates, length(delay_data[,1])))
  analyze_nd(delay_data.xts, scaling_method, returns = FALSE,  max_scale, K_max, window)
}

output <- function(tmp, filename , plot = "FALSE") 
{
  write.zoo(tmp, file = filename)
  if (plot == "TRUE") {
    plot(tmp, type = 'l')
  }
}


get_impact_window <- function(data, index, window_length)
{
  data[index:(index+window_length-1)]
}
