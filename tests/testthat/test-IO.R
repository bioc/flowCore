context("flowSet/flowFrame IO...")
# expectRes <- readRDS("tests/testthat/expectResults.rds")
data(GvHD)
fs <- GvHD[1:2]
expectPD <- pData(fs)
expectPD[["Patient"]] <- as.integer(as.vector(expectPD[["Patient"]]))
expectPD[["Visit"]] <- as.integer(expectPD[["Visit"]])
expectPD[["name"]] <- I(paste0(expectPD[["name"]], ".fcs"))
rownames(expectPD) <- paste0(rownames(expectPD), ".fcs")

tmpdir <- tempfile()

write.flowSet(fs, tmpdir)

test_that("read.flowSet", {
      
      files <- list.files(tmpdir, pattern = "fcs")
      #no phenoData supplied
      fs1 <- read.flowSet(files, path = tmpdir)
      expect_equivalent(pData(fs1), expectPD[, "name", drop = F])
      
      
      anno <- list.files(tmpdir, pattern = "txt", full = T)
      pd <- Biobase::read.AnnotatedDataFrame(anno)
      pd[["name"]] <- I(paste0(pd[["name"]], ".fcs"))
      #with phenoData supplied
      suppressWarnings(fs1 <- read.flowSet(files, path = tmpdir, phenoData = pd))
      pData(fs1)["FCS_File"] <- NULL
      expect_equal(pData(fs1), expectPD)
      
      #pd without name
      pData(pd)[["name"]] <- NULL
      suppressWarnings(fs1 <- read.flowSet(files, path = tmpdir, phenoData = pd))
      pData(fs1)[["name"]] <- I(pData(fs1)[["name"]])
      pData(fs1)["FCS_File"] <- NULL
      expect_equal(pData(fs1), expectPD)
      
      #pd with wrong name
      pd <- Biobase::read.AnnotatedDataFrame(anno)
      pData(pd)[["name"]] <- paste0(pData(pd)[["name"]], "dummy")
      suppressWarnings(fs1 <- read.flowSet(files, path = tmpdir, phenoData = pd))
      expect_equal(pData(fs1), pData(pd))
      
      #create duplicated folder
      tmpdir1 <- tempfile()
      suppressWarnings(write.flowSet(fs, tmpdir1))
      #try to read both folders in
      files <- list.files(tmpdir, pattern = "fcs", full = T)
      files1 <- list.files(tmpdir1, pattern = "fcs", full = T)
      fs2 <- read.flowSet(c(files, files1))
      #check duplicates
      sn <- basename(files)
      sn1 <- paste0(sn, ".1")
      expect_equal(sampleNames(fs2), c(sn, sn1))
      
    })

test_that("phenoData<-", {
      pd <- expectPD
      
      # without name column
      pd[["name"]] <- NULL
      
      sampleNames(fs) <- paste0(sampleNames(fs), ".fcs") 
      pData(fs) <- pd
      #name column is added
      expect_equal(expectPD[["name"]], I(pData(fs)[["name"]]))
      
      # name to be different from rownames
      pd[["name"]] <- letters[1:2] 
      pData(fs) <- pd
      expect_equal(pData(fs)[["name"]], pd[["name"]])
      expect_equal(rownames(pData(fs)), rownames(expectPD))
      
      
    })

test_that("test write.FCS", {
  fcsfile <- system.file("extdata/CytoTrol_CytoTrol_1.fcs", package = "flowWorkspaceData")
  fr <- read.FCS(fcsfile)
  tmp <- tempfile()
  
  #change desc col
  pData(parameters(fr))[6, "desc"] <- "38"
  # Write to file
  tmp <- tempfile()
  write.FCS(fr,tmp)
  fr1 <- read.FCS(tmp)
  expect_equal(markernames(fr1)[2], "38")
  
  # When I read the file back in, the SPILL matrix appears to be malformed.
  fr <- read.FCS(fcsfile)
  expect_equal(keyword(fr)[["transformation"]], "applied")
  keyword(fr)[["FILENAME"]] <- "setToDummy"
  expect_equal(expectRes[["read.FCS"]][["NHLBI"]], digest(fr))
  
  write.FCS(fr,tmp)
  fr1 <- read.FCS(tmp)
  keys <- description(fr)
  keys[["$TOT"]] <- trimws(keys[["$TOT"]])
  keys[c("$BEGINDATA", "$ENDDATA")] <- NULL
  keys.new <- description(fr1)
  keys.new[["FILENAME"]] <- "setToDummy"
  expect_equal(keys.new[names(keys)], keys)
  expect_equivalent(exprs(fr), exprs(fr1))
  
  #disable default linearize trans
  fr_notrans <- read.FCS(fcsfile, transformation = FALSE)
  expect_null(keyword(fr_notrans)[["transformation"]])
  #flowCore_$PnR and transformation keywords should be absent now
  #and there are should be no other difference in keywords between the two read
  missing.keys <- names(keys)[which(!names(keys) %in% names(description(fr_notrans)))]
  expect_equal(length(missing.keys), 25)
  expect_true(all(grepl("(flowCore_\\$P)|(transformation)", missing.keys)))
  #any the resulted write will produce no trans related keyword r
  suppressWarnings(write.FCS(fr_notrans,tmp))
  fr1 <- read.FCS(tmp, transformation = FALSE)
  missing.keys <- names(keys)[which(!names(keys) %in% names(description(fr1)))]
  expect_equal(length(missing.keys), 25)
  expect_true(all(grepl("(flowCore_\\$P)|(transformation)", missing.keys)))
  # when default linearize is enabled
  fr1 <- read.FCS(tmp)
  missing.keys <- names(keys)[which(!names(keys) %in% names(description(fr1)))]
  expect_equal(length(missing.keys), 0)
  
  #transform fr
  fr.trans <- transform(fr_notrans, estimateLogicle(fr_notrans, markernames(fr_notrans)))
  expect_equal(keyword(fr.trans)[["transformation"]], "custom")
  #new keywords flowCore_$P* has been inserted
  missing.keys <- names(keys)[which(!names(keys) %in% names(description(fr.trans)))]
  expect_equal(length(missing.keys), 0)
  suppressWarnings(write.FCS(fr.trans,tmp))
  #these keywords remains even disable trans when read  it back
  fr1 <- read.FCS(tmp, transformation = FALSE)
  expect_equal(keyword(fr1)[["transformation"]], "custom")
  missing.keys <- names(keys)[which(!names(keys) %in% names(description(fr1)))]
  expect_equal(length(missing.keys), 0)
  #and transformation flag has no effect on read when it is already custom
  fr1 <- read.FCS(tmp)
  expect_equal(keyword(fr1)[["transformation"]], "custom")
  missing.keys <- names(keys)[which(!names(keys) %in% names(description(fr1)))]
  expect_equal(length(missing.keys), 0)
  
  
  # test delimiter(\) escaping 
  description(fr)[["$DATE"]] <- "05\\JUN\\2012"
  suppressWarnings(write.FCS(fr,tmp))
  fr1 <- read.FCS(tmp, emptyValue = F)
  keys.new <- description(fr1)
  keys.new[["FILENAME"]] <- "setToDummy"
  expect_equal(keys.new[["$DATE"]], "05\\\\JUN\\\\2012")
  keys.new[["$DATE"]] <- keys[["$DATE"]]
  expect_equal(keys.new[names(keys)], keys)
  expect_equivalent(exprs(fr), exprs(fr1))
  
  # write it again to see if the existing double delimiter is handled properly
  suppressWarnings(write.FCS(fr1,tmp))
  fr1 <- read.FCS(tmp, emptyValue = F)
  keys.new <- description(fr1)
  keys.new[["FILENAME"]] <- "setToDummy"
  expect_equal(keys.new[["$DATE"]], "05\\\\JUN\\\\2012")
  keys.new[["$DATE"]] <- keys[["$DATE"]]
  expect_equal(keys.new[names(keys)], keys)
  expect_equivalent(exprs(fr), exprs(fr1))
  
  #test other delimiter
  suppressWarnings(write.FCS(fr,tmp, delimiter = ";"))
  fr1 <- read.FCS(tmp, emptyValue = F)
  keys.new <- description(fr1)
  keys.new[["FILENAME"]] <- "setToDummy"
  expect_equal(keys.new[["$DATE"]], "05\\JUN\\2012")
  keys.new[["$DATE"]] <- keys[["$DATE"]]
  expect_equal(keys.new[names(keys)], keys)
  expect_equivalent(exprs(fr), exprs(fr1))
  
  #when colmn.pattern is used to subset channels in read.FCS
  #make sure the id in $Pn is set properly in write.FCS
  fr_sub <- read.FCS(fcsfile, column.pattern = '-A')
  tmp <- tempfile()
  suppressWarnings(write.FCS(fr_sub , filename = tmp))
  fr1 <- read.FCS(tmp)
  expect_equal(pData(parameters(fr_sub))[["name"]], pData(parameters(fr1))[["name"]], check.attributes = FALSE)
  expect_equal(pData(parameters(fr_sub))[["desc"]], pData(parameters(fr1))[["desc"]], check.attributes = FALSE)
  
  
})

test_that("write.flowSet: test2", {
  
  data(GvHD)
  foo <- GvHD[1:2]
  
  
  ## now write out into  files
  outDir <- tempfile()
  suppressWarnings(write.flowSet(foo, outDir))
  expect_equal(dir(outDir), c("annotation.txt", "s5a01.fcs", "s5a02.fcs"))
  
  outDir <- tempfile()
  suppressWarnings(write.flowSet(foo, outDir, filename = c("a")))
  expect_equal(dir(outDir), c("1_a.fcs", "2_a.fcs", "annotation.txt"))
  
  outDir <- tempfile()
  suppressWarnings(write.flowSet(foo, outDir, filename = c("a", "b")))
  expect_equal(dir(outDir), c("a.fcs", "annotation.txt", "b.fcs"))
  
})


test_that("read.FCS: channel_alias", {
  
  data(GvHD)
  fr1 <- GvHD[[1]]
  fr2 <- GvHD[[2]]
  
  colnames(fr1)[c(3,5)] <- c("AL1-H", "AL3-H")
  
  ## now write out into  files
  fcs1 <- tempfile()
  write.FCS(fr1, fcs1)
  fcs2 <- tempfile()
  write.FCS(fr2, fcs2)
  
  expect_message(expect_error(fs <- read.flowSet(c(fcs1,fcs2))),regexp = "doesn't have the identical colnames")
  
  #strict matching by full name
  map <- data.frame(alias = c("FL1", "FL3"), channels = c("AL1-H, FL1-H", "FL3-H, AL3-H"))
  fs <- read.flowSet(c(fcs1,fcs2), channel_alias = map)
  expect_equal(colnames(fs)[c(3,5)], c("FL1", "FL3"))
  
  #partial matching
  map <- data.frame(alias = c("FL1", "FL3"), channels = c("AL1, FL1", "FL3, AL3"))
  fs <- read.flowSet(c(fcs1,fcs2), channel_alias = map)
  expect_equal(colnames(fs)[c(3,5)], c("FL1", "FL3"))
  
  #case insensitive matching
  map <- data.frame(alias = c("FL1", "FL3"), channels = c("al1, FL1", "fl3, AL3"))
  fs <- read.flowSet(c(fcs1,fcs2), channel_alias = map)
  expect_equal(colnames(fs)[c(3,5)], c("FL1", "FL3"))
  
  #ambigous partial matching
  map <- data.frame(alias = c("FL1", "FL3"), channels = c("l1, FL1", "fl3, AL3"))
  expect_error(fs <- read.flowSet(c(fcs1,fcs2), channel_alias = map), "multiple entries")
  
  outDir <- tempfile()
  suppressWarnings(write.flowSet(fs, outDir, filename = c("a", "b")))
  fs1 <- read.flowSet(files = c("a.fcs", "b.fcs"), path = outDir)
  expect_equal(keyword(fs1[[1]])[["$P3N"]], "FL1")
  
  #update spillover as well
  fcsfile <- system.file("extdata/CytoTrol_CytoTrol_1.fcs", package = "flowWorkspaceData")
  fr <- read.FCS(fcsfile, channel_alias = data.frame(alias = c("FL1", "FL3"), channels = c("B710-A", "R780-A")))
  expect_equal(colnames(spillover(fr)[[1]]), colnames(fr)[5:11])
  
  #validity check on possible multiple channels matching to the same alias within one FCS
  fcsfile <- system.file("extdata/CytoTrol_CytoTrol_1.fcs", package = "flowWorkspaceData")
  expect_error(fr <- read.FCS(fcsfile, channel_alias = data.frame(alias = c("FL1", "FL3"), channels = c("B710-A,V545", "R780-A"))), "channel_alias: Multiple channels from one FCS")
  
})
