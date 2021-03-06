

context("timeout")


test_that("Resampling with slowLearner takes as long as expected", {

  configureMlr(on.learner.error = "stop")
  for (backend in c("native", "fork")) {
    setDefaultRWTBackend(backend)

    sl = setHyperPars(slowLearner, trainlag = c(1, 1, 1, 1, 1), predictlag = c(1, 1, 1, 1, 1), rate = 0.5)

    houtRunTime = system.time(resample(sl, pid.task, hout, show.info = FALSE), FALSE)[3]
    expect_true(houtRunTime >= 2 && houtRunTime < 4)

    cv3RunTime = system.time(resample(sl, pid.task, cv3, show.info = FALSE), FALSE)[3]
    expect_true(cv3RunTime >= 6 && cv3RunTime < 12)
  }

})

test_that("Resampling with large enough timeout works", {

  configureMlr(on.learner.error = "stop")

  for (backend in c("native", "fork")) {
    setDefaultRWTBackend(backend)

    tcw = makeTimeconstraintWrapper(slowLearner, 4)
    sl = setHyperPars(tcw, trainlag = c(1, 1, 1, 1, 1), predictlag = c(1, 1, 1, 1, 1), rate = 0.5)

    houtRunTime = system.time(r <- resample(sl, pid.task, hout, show.info = FALSE), FALSE)[3]
    expect_true(houtRunTime >= 2 && houtRunTime < 4)
    expect_false(is.na(r$aggr))

    cv3RunTime = system.time(r <- resample(sl, pid.task, cv3, show.info = FALSE), FALSE)[3]
    expect_true(cv3RunTime >= 6 && cv3RunTime < 12)
    expect_false(is.na(r$aggr))
  }

})

test_that("Resampling that times out on iters that are not the first gives partial results", {

  configureMlr(on.learner.error = "warn")
  for (backend in c("native", "fork")) {
    setDefaultRWTBackend(backend)

    tcw = makeTimeconstraintWrapper(slowLearner, 1)
    sl = setHyperPars(tcw, trainlag = c(.1, 10, .1, .5, .1), predictlag = c(.1, .1, 10, 10, .1), rate = 0.5)

    houtRunTime = system.time(r <- resample(sl, pid.task, hout, show.info = FALSE), FALSE)[3]
    expect_true(houtRunTime <= 2)
    expect_false(is.na(r$aggr))

    cv5RunTime = system.time(expect_warning(r <- resample(sl, pid.task, cv5, show.info = FALSE),
      "TimeoutWrapper Timeout", all = TRUE), FALSE)[3]
    expect_true(cv5RunTime <= 25)  # need generous time buffer since 'fork' backend creates additional lag
    expect_true(is.na(r$aggr))
    expect_true(all(is.na(r$measures.test$mmce) == c(F, T, T, T, F)))
  }

})

test_that("Resampling timeout on first iteration aborts resampling", {
  configureMlr(on.learner.error = "warn")
  for (backend in c("native", "fork")) {
    setDefaultRWTBackend(backend)

    tcw = makeTimeconstraintWrapper(slowLearner, 1)
    sl = setHyperPars(tcw, trainlag = c(4, 4, .1, 2, .1), predictlag = c(4, .1, 4, 2, .1), rate = 0.5)

    houtRunTime = system.time(expect_warning(r <- resample(sl, pid.task, hout, show.info = FALSE),
      "TimeoutWrapper Timeout", all = TRUE), FALSE)[3]
    expect_true(houtRunTime <= 4)
    expect_true(is.na(r$aggr))

    cv5RunTime = system.time(expect_warning(r <- resample(sl, pid.task, cv5, show.info = FALSE),
      "TimeoutWrapper Timeout|First resampling run was timeout",
      all = TRUE), FALSE)[3]
    expect_true(cv5RunTime <= 6)
    expect_true(is.na(r$aggr))
    expect_true(all(is.na(r$measures.test$mmce)))
  }

})

test_that("Resampling timeout on first iteration with generous timeFirstIter does not abort", {

  configureMlr(on.learner.error = "warn")
  for (backend in c("native", "fork")) {
    setDefaultRWTBackend(backend)

    tcw = makeTimeconstraintWrapper(slowLearner, 1, 10)
    sl = setHyperPars(tcw, trainlag = c(4, 4, .1, 2, .1), predictlag = c(4, .1, 4, 2, .1), rate = 0.5)

    # only one resampling iter: 1s timeout
    houtRunTime = system.time(expect_warning(r <- resample(sl, pid.task, hout, show.info = FALSE),
      "TimeoutWrapper Timeout", all = TRUE), FALSE)[3]
    expect_true(houtRunTime <= 4)
    expect_true(is.na(r$aggr))

    cv5RunTime = system.time(expect_warning(r <- resample(sl, pid.task, cv5, show.info = FALSE),
      "TimeoutWrapper Timeout", all = TRUE), FALSE)[3]
    expect_true(cv5RunTime <= 20 && cv5RunTime >= 11)
    expect_true(is.na(r$aggr))
    expect_true(all(is.na(r$measures.test$mmce) == c(T, T, T, T, F)))
  }

})



test_that("automlr works when timelimits are not breached", {

  for (backend in c("native", "fork")) {
    for (amlrbackend in c("random", "irace", "mbo")) {

      setDefaultRWTBackend(backend)
      sl = setHyperPars(slowLearner, trainlag = c(.01, 0, 0, 0, 0), predictlag = c(.1, .1, .1, .1, .1))
      runtime = system.time(res <- automlr(pid.task, budget = c(walltime = 5), backend = amlrbackend, verbosity = 0, searchspace = list(slAL(sl)),
                                 max.walltime.overrun = 120, max.learner.time = 10), FALSE)[3]
      expect_gt(runtime, 5)
      expect_lt(runtime, 125)
      expect_gt(nrow(as.data.frame(amfinish(res)$opt.path)), 1)
    }
  }

})

test_that("automlr is gentle when max.walltime.overrun is not breached", {

  for (backend in c("native", "fork")) {
    for (amlrbackend in "random") {  # 'irace' and 'mbo' were tested above.
      setDefaultRWTBackend(backend)

      backendObj = automlr:::registered.backend[[amlrbackend]](resampling=hout)

      sl = setHyperPars(slowLearner, trainlag = c(5, 1, 1, 1, 1), predictlag = c(5, 1, 1, 1, 1))
      runtime = system.time(res <- automlr(pid.task, budget = c(walltime = 7), backend = backendObj, verbosity = 0, searchspace = list(slAL(sl)),
                                 max.walltime.overrun = 60, max.learner.time = 30), FALSE)[3]
      expect_gt(runtime, 7)
      expect_lt(runtime, 14)

      expect_equal(nrow(as.data.frame(amfinish(res)$opt.path)), 1)
      expect_false(is.na(amfinish(res)$opt.val))
    }
  }
})

test_that("automlr kills the run if max.walltime.overrun is breached", {

  for (backend in c("native", "fork")) {
    for (amlrbackend in list("random", "mbo")) {  # TODO: irace, once it is faster
      setDefaultRWTBackend(backend)

      backendObj = automlr:::registered.backend[[amlrbackend]](resampling=hout)
      env = new.env()
      env$sleep = FALSE
      sl = setHyperPars(slowLearner, trainlag = c(5, 1, 1, 1, 1),
        predictlag = c(5, 1, 1, 1, 1),
        env = env)

      res = automlr(pid.task, budget = c(evals = 1),
        backend = backendObj, verbosity = 0, searchspace = list(slAL(sl)))
      env$sleep = TRUE

      runtime = system.time(res2 <- automlr(res, budget = res$spent["walltime"] + 14,
        max.walltime.overrun = 2), FALSE)[3]
      expect_gt(runtime, 16)
      expect_lt(runtime, 20)
      offset = nrow(as.data.frame(amfinish(res)$opt.path))

      expectednew = switch(amlrbackend, random = 2, mbo = 1, irace = 0)

      expect_equal(nrow(as.data.frame(amfinish(res2)$opt.path)), expectednew + offset)
      if (expectednew >= 2) {
        expect_equal(as.data.frame(amfinish(res2)$opt.path)$error.message[2 + offset],
          "timeout")
      }
      expect_false(is.na(amfinish(res)$opt.val))
    }
  }

})

test_that("automlr respects max.learner.time", {

  for (backend in c("native", "fork")) {
    for (amlrbackend in list("random", "mbo")) {  # TODO: irace, once it is faster
      setDefaultRWTBackend(backend)

      backendObj = automlr:::registered.backend[[amlrbackend]](resampling=hout)

      env = new.env()
      env$sleep = FALSE
      sl = setHyperPars(slowLearner, trainlag = c(5, 1, 1, 1, 1),
        predictlag = c(5, 1, 1, 1, 1),
        env = env)

      res = automlr(pid.task, budget = c(evals = 1),
        backend = backendObj, verbosity = 0, searchspace = list(slAL(sl)),
        max.learner.time = 2)
      env$sleep = TRUE

      runtime = system.time(res2 <- automlr(res, budget = res$spent["walltime"] + 8,
        max.walltime.overrun = 120), FALSE)[3]
      expect_gt(runtime, 8)
      expect_lt(runtime, 16)
      offset = nrow(as.data.frame(amfinish(res)$opt.path))
      expect_gte(nrow(as.data.frame(amfinish(res2)$opt.path)), 2 + offset)
      expect_lte(nrow(as.data.frame(amfinish(res2)$opt.path)), 5 + offset)
      expect_false(is.na(amfinish(res2)$opt.val))
      errmsg = switch(amlrbackend, random = "TimeoutWrapper Timeout",
        mbo = "Imputed invalid objective function output")
      expect_true(any(grepl(errmsg, as.data.frame(amfinish(res2)$opt.path)$error.message)))
    }
  }

})

