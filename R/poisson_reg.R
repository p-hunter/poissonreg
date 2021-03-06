#' General Interface for Poisson Regression Models
#'
#' `poisson_reg()` is a way to generate a _specification_ of a model
#'  before fitting and allows the model to be created using
#'  different packages in R or Stan. The main
#'  arguments for the model are:
#' \itemize{
#'   \item \code{penalty}: The total amount of regularization
#'  in the model. Note that this must be zero for some engines.
#'   \item \code{mixture}: The mixture amounts of different types of
#'   regularization (see below). Note that this will be ignored for some engines.
#' }
#' These arguments are converted to their specific names at the
#'  time that the model is fit. Other options and argument can be
#'  set using `set_engine()`. If left to their defaults
#'  here (`NULL`), the values are taken from the underlying model
#'  functions. If parameters need to be modified, `update()` can be used
#'  in lieu of recreating the object from scratch.
#' @param mode A single character string for the type of model.
#'  The only possible value for this model is "regression".
#' @param penalty A non-negative number representing the total
#'  amount of regularization (`glmnet` only).
#' @param mixture A number between zero and one (inclusive) that is the
#'  proportion of L1 regularization (i.e. lasso) in the model. When
#'  `mixture = 1`, it is a pure lasso model while `mixture = 0` indicates that
#'  ridge regression is being used. (`glmnet` and `spark` only).
#' @details
#' The data given to the function are not saved and are only used
#'  to determine the _mode_ of the model. For `poisson_reg()`, the
#'  mode will always be "regression".
#'
#' The model can be created using the `fit()` function using the
#'  following _engines_:
#' \itemize{
#' \item \pkg{R}:  `"glm"`  (the default), `"glmnet"`, `"hurdle"`, or `"zeroinfl"`
#' \item \pkg{Stan}:  `"stan"`
#' }
#'
#' @includeRmd man/rmd/poission-reg-engine.Rmd details
#'
#' For `glmnet` models, the full regularization path is always fit regardless
#' of the value given to `penalty`. Also, there is the option to pass
#'  multiple values (or no values) to the `penalty` argument. When using the
#'  `predict()` method in these cases, the return value depends on
#'  the value of `penalty`. When using `predict()`, only a single
#'  value of the penalty can be used. When predicting on multiple
#'  penalties, the `multi_predict()` function can be used. It
#'  returns a tibble with a list column called `.pred` that contains
#'  a tibble with all of the penalty results.
#'
#' For prediction, the `stan` engine can compute posterior
#'  intervals analogous to confidence and prediction intervals. In
#'  these instances, the units are the original outcome and when
#'  `std_error = TRUE`, the standard deviation of the posterior
#'  distribution (or posterior predictive distribution as
#'  appropriate) is returned.
#'
#' For the `hurdle` or `zeroinfl` engines, note that an extended formula can be
#' used to add a model for the zero-count values. Using [fit()] for training,
#' that extended formula can be passed as usual. For [fit_xy()], the result
#' will be to model the zero-counts with all of the predictors.
#'
#' @examples
#' poisson_reg()
#'
#' # Model from Agresti (2007) Table 7.6
#' log_lin_mod <-
#'   poisson_reg() %>%
#'   set_engine("glm") %>%
#'   fit(count ~ (.)^2, data = seniors)
#'
#' summary(log_lin_mod$fit)
#'
#' # ------------------------------------------------------------------------------
#'
#' library(pscl)
#'
#' data("bioChemists", package = "pscl")
#'
#' poisson_reg() %>%
#'   set_engine("hurdle") %>%
#' # Extended formula:
#'   fit(art ~ . | phd, data = bioChemists)
#'
#' @export
#' @importFrom purrr map_lgl
poisson_reg <-
  function(mode = "regression",
           penalty = NULL,
           mixture = NULL) {

    args <- list(
      penalty = enquo(penalty),
      mixture = enquo(mixture)
    )

    parsnip::new_model_spec(
      "poisson_reg",
      args = args,
      eng_args = NULL,
      mode = mode,
      method = NULL,
      engine = NULL
    )
  }

#' @export
print.poisson_reg <- function(x, ...) {
  cat("Poisson Regression Model Specification (", x$mode, ")\n\n", sep = "")
  model_printer(x, ...)

  if (!is.null(x$method$fit$args)) {
    cat("Model fit template:\n")
    print(show_call(x))
  }

  invisible(x)
}


#' @export
translate.poisson_reg <- function(x, engine = x$engine, ...) {
  x <- parsnip::translate.default(x, engine, ...)

  if (engine == "glmnet") {
    # See discussion in https://github.com/tidymodels/parsnip/issues/195
    x$method$fit$args$lambda <- NULL
    # Since the `fit` infomration is gone for the penalty, we need to have an
    # evaludated value for the parameter.
    x$args$penalty <- rlang::eval_tidy(x$args$penalty)
  }

  x
}


# ------------------------------------------------------------------------------

#' @param object A boosted tree model specification.
#' @param parameters A 1-row tibble or named list with _main_
#'  parameters to update. If the individual arguments are used,
#'  these will supersede the values in `parameters`. Also, using
#'  engine arguments in this object will result in an error.
#' @param ... Not used for `update()`.
#' @param fresh A logical for whether the arguments should be
#'  modified in-place of or replaced wholesale.
#' @return An updated model specification.
#' @examples
#' model <- poisson_reg(penalty = 10, mixture = 0.1)
#' model
#' update(model, penalty = 1)
#' update(model, penalty = 1, fresh = TRUE)
#' @method update poisson_reg
#' @rdname poisson_reg
#' @export
update.poisson_reg <-
  function(object,
           parameters = NULL,
           penalty = NULL, mixture = NULL,
           fresh = FALSE, ...) {
    update_dot_check(...)

    if (!is.null(parameters)) {
      parameters <- check_final_param(parameters)
    }
    args <- list(
      penalty = enquo(penalty),
      mixture = enquo(mixture)
    )

    args <- update_main_parameters(args, parameters)

    if (fresh) {
      object$args <- args
    } else {
      null_args <- map_lgl(args, null_value)
      if (any(null_args))
        args <- args[!null_args]
      if (length(args) > 0)
        object$args[names(args)] <- args
    }

    parsnip::new_model_spec(
      "poisson_reg",
      args = object$args,
      eng_args = object$eng_args,
      mode = object$mode,
      method = NULL,
      engine = object$engine
    )
  }

# ------------------------------------------------------------------------------

check_args.poisson_reg <- function(object) {

  args <- lapply(object$args, rlang::eval_tidy)

  if (all(is.numeric(args$penalty)) && any(args$penalty < 0))
    rlang::abort("The amount of regularization should be >= 0.")
  if (is.numeric(args$mixture) && (args$mixture < 0 | args$mixture > 1))
    rlang::abort("The mixture proportion should be within [0,1].")
  if (is.numeric(args$mixture) && length(args$mixture) > 1)
    rlang::abort("Only one value of `mixture` is allowed.")

  invisible(object)
}

# ------------------------------------------------------------------------------

organize_glmnet_pred <- function(x, object) {
  if (ncol(x) == 1) {
    res <- x[, 1]
    res <- unname(res)
  } else {
    n <- nrow(x)
    res <- utils::stack(as.data.frame(x))
    if (!is.null(object$spec$args$penalty))
      res$lambda <- rep(object$spec$args$penalty, each = n) else
        res$lambda <- rep(object$fit$lambda, each = n)
    res <- res[, colnames(res) %in% c("values", "lambda")]
  }
  res
}


# ------------------------------------------------------------------------------

# For `predict` methods that use `glmnet`, we have specific methods.
# Only one value of the penalty should be allowed when called by `predict()`:

check_penalty <- function(penalty = NULL, object, multi = FALSE) {

  if (is.null(penalty)) {
    penalty <- object$fit$lambda
  }

  # when using `predict()`, allow for a single lambda
  if (!multi) {
    if (length(penalty) != 1)
      rlang::abort(
        glue::glue(
          "`penalty` should be a single numeric value. `multi_predict()` ",
          "can be used to get multiple predictions per row of data.",
        )
      )
  }

  if (length(object$fit$lambda) == 1 && penalty != object$fit$lambda)
    rlang::abort(
      glue::glue(
        "The glmnet model was fit with a single penalty value of ",
        "{object$fit$lambda}. Predicting with a value of {penalty} ",
        "will give incorrect results from `glmnet()`."
      )
    )

  penalty
}

# ------------------------------------------------------------------------------
# glmnet call stack for poissom regression using `predict` when object has
# classes "_fishnet" and "model_fit":
#
#  predict()
# 	predict._fishnet(penalty = NULL)   <-- checks and sets penalty
#    predict.model_fit()             <-- checks for extra vars in ...
#     predict_numeric()
#      predict_numeric._fishnet()
#       predict_numeric.model_fit()
#        predict.fishnet()


# glmnet call stack for poisson regression using `multi_predict` when object has
# classes "_fishnet" and "model_fit":
#
# 	multi_predict()
#    multi_predict._fishnet(penalty = NULL)
#      predict._fishnet(multi = TRUE)          <-- checks and sets penalty
#       predict.model_fit()                  <-- checks for extra vars in ...
#        predict_raw()
#         predict_raw._fishnet()
#          predict_raw.model_fit(opts = list(s = penalty))
#           predict.fishnet()


#' @export
predict._fishnet <-
  function(object, new_data, type = NULL, opts = list(), penalty = NULL, multi = FALSE, ...) {
    if (any(names(enquos(...)) == "newdata"))
      rlang::abort("Did you mean to use `new_data` instead of `newdata`?")

    # See discussion in https://github.com/tidymodels/parsnip/issues/195
    if (is.null(penalty) & !is.null(object$spec$args$penalty)) {
      penalty <- object$spec$args$penalty
    }

    object$spec$args$penalty <- check_penalty(penalty, object, multi)

    object$spec <- parsnip::eval_args(object$spec)
    predict.model_fit(object, new_data = new_data, type = type, opts = opts, ...)
  }

#' @export
predict_numeric._fishnet <- function(object, new_data, ...) {
  if (any(names(enquos(...)) == "newdata"))
    rlang::abort("Did you mean to use `new_data` instead of `newdata`?")

  object$spec <- parsnip::eval_args(object$spec)
  parsnip::predict_numeric.model_fit(object, new_data = new_data, ...)
}

#' Model predictions across many sub-models
#'
#' For some models, predictions can be made on sub-models in the model object.
#' @param object A `model_fit` object.
#' @param new_data A rectangular data object, such as a data frame.
#' @param opts A list of options..
#' @param ... Optional arguments to pass to `predict.model_fit(type = "raw")`
#'  such as `type`.
#' @return A tibble with the same number of rows as the data being predicted.
#'  There is a list-column named `.pred` that contains tibbles with
#'  multiple rows per sub-model.
#' @export
#' @keywords internal
predict_raw._fishnet <- function(object, new_data, opts = list(), ...)  {
  if (any(names(enquos(...)) == "newdata")) {
    rlang::abort("Did you mean to use `new_data` instead of `newdata`?")
  }

  object$spec <- parsnip::eval_args(object$spec)
  opts$s <- object$spec$args$penalty
  parsnip::predict_raw.model_fit(object, new_data = new_data, opts = opts, ...)
}

#' @importFrom dplyr full_join as_tibble arrange
#' @importFrom tidyr gather
#' @export
#' @rdname predict_raw._fishnet
#' @param penalty A numeric vector of penalty values.
multi_predict._fishnet <-
  function(object, new_data, type = NULL, penalty = NULL, ...) {
    if (any(names(enquos(...)) == "newdata"))
      rlang::abort("Did you mean to use `new_data` instead of `newdata`?")

    dots <- list(...)

    object$spec <- eval_args(object$spec)

    if (is.null(penalty)) {
      # See discussion in https://github.com/tidymodels/parsnip/issues/195
      if (!is.null(object$spec$args$penalty)) {
        penalty <- object$spec$args$penalty
      } else {
        penalty <- object$fit$lambda
      }
    }

    pred <- predict._fishnet(object, new_data = new_data, type = "raw",
                             opts = dots, penalty = penalty, multi = TRUE)
    param_key <- tibble(group = colnames(pred), penalty = penalty)
    pred <- as_tibble(pred)
    pred$.row <- 1:nrow(pred)
    pred <- gather(pred, group, .pred, -.row)
    pred <- full_join(param_key, pred, by = "group")
    pred$group <- NULL
    pred <- arrange(pred, .row, penalty)
    .row <- pred$.row
    pred$.row <- NULL
    pred <- split(pred, .row)
    names(pred) <- NULL
    tibble(.pred = pred)
  }
